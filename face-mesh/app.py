"""
Face landmark detection service for MySkin.

Single endpoint POST /detect that takes raw image bytes and returns a
face_geom payload in normalised (0..1) coordinates — the exact shape the
mobile renderer expects:

    {
      "found": true,
      "bbox":     [x0, y0, x1, y1],
      "contour":  [[x, y], ...],            # 36 points around the face oval
      "landmarks": {
        "forehead":    [x, y],
        "tzone":       [x, y],
        "left_cheek":  [x, y],              # photo-left side
        "right_cheek": [x, y],
        "chin":        [x, y]
      }
    }

When no face is detected the response is {"found": false, "reason": ...}.

Uses MediaPipe Face Mesh — same model used in production filter apps.
468 landmarks, sub-pixel accuracy, beard/lighting/skin-tone independent.
"""

from __future__ import annotations

import io
import os
from typing import Optional

import cv2
import mediapipe as mp
import numpy as np
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from PIL import Image, ImageOps

app = FastAPI(title="MySkin face-mesh", version="1.0.0")

# Reuse a single FaceMesh instance — initialising the graph is expensive
# (~500ms cold). static_image_mode=True so each request is independent
# (no temporal smoothing across calls).
_face_mesh = mp.solutions.face_mesh.FaceMesh(
    static_image_mode=True,
    max_num_faces=1,
    refine_landmarks=False,
    min_detection_confidence=0.4,
)

# Trigger MediaPipe graph initialisation at import time, not on the first
# real request. Without this the first user scan pays a ~3-5s cold start
# that often trips the upstream client's timeout. We pass a tiny blank
# image — the graph initialises the same way as for a real call.
try:
    _warmup = np.zeros((128, 128, 3), dtype=np.uint8)
    _face_mesh.process(_warmup)
except Exception as _warm_err:  # pragma: no cover
    print(f"face-mesh warmup skipped: {_warm_err}")

# Canonical 36-point face-oval polygon (MediaPipe Face Mesh indices),
# ordered around the perimeter. Used to draw the dashed outline overlay.
FACE_OVAL = [
    10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288,
    397, 365, 379, 378, 400, 377, 152, 148, 176, 149, 150, 136,
    172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109,
]

# Anatomical zone anchors. Indices picked from the MediaPipe Face Mesh
# topology so they land on actual skin even on bearded faces:
#   forehead  — top-centre of the forehead, well above the brows
#   tzone     — bridge of the nose (T-shape stem)
#   chin      — chin pad, just above the jaw bottom
#   cheeks    — apple of the cheek (cheekbone bulge)
ZONE_INDICES = {
    "forehead": 10,    # top of forehead, between brows when projected down
    "tzone": 6,        # mid nose bridge (between the eyes vertically)
    "chin": 152,       # chin tip
    "cheek_a": 50,     # one cheek apple
    "cheek_b": 280,    # the other cheek apple
}


def _read_image(data: bytes) -> np.ndarray:
    """Decode arbitrary image bytes (jpg/png/heic-as-jpg) into BGR ndarray,
    honouring EXIF orientation so MediaPipe sees an upright face.
    """
    try:
        pil = Image.open(io.BytesIO(data))
        # EXIF transpose is the single most common source of "landmarks
        # rotated 90°" bugs — apply once at the boundary, never again.
        pil = ImageOps.exif_transpose(pil)
        pil = pil.convert("RGB")
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"bad_image: {e}")

    arr = np.asarray(pil)
    # MediaPipe wants RGB, but we keep BGR convention internally because
    # downstream cv2 ops use it. Convert at the FaceMesh call site.
    return cv2.cvtColor(arr, cv2.COLOR_RGB2BGR)


def _detect(bgr: np.ndarray) -> Optional[dict]:
    h, w = bgr.shape[:2]
    if h == 0 or w == 0:
        return None
    rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
    result = _face_mesh.process(rgb)
    if not result.multi_face_landmarks:
        return None

    lm = result.multi_face_landmarks[0].landmark

    def pt(idx: int) -> list[float]:
        p = lm[idx]
        # MediaPipe returns normalised coords already in [0, 1]. Clamp to
        # defend against marginal off-by-one due to subpixel rounding.
        return [
            float(min(max(p.x, 0.0), 1.0)),
            float(min(max(p.y, 0.0), 1.0)),
        ]

    # Bbox from the extents of all 468 landmarks — tighter and more
    # honest than MediaPipe's separate face-detector bbox.
    xs = [min(max(p.x, 0.0), 1.0) for p in lm]
    ys = [min(max(p.y, 0.0), 1.0) for p in lm]
    bbox = [min(xs), min(ys), max(xs), max(ys)]

    contour = [pt(i) for i in FACE_OVAL]

    cheek_a = pt(ZONE_INDICES["cheek_a"])
    cheek_b = pt(ZONE_INDICES["cheek_b"])
    # Label-by-position: whichever cheek is photographically on the left
    # of the image (smaller x) becomes "left_cheek". Mobile labels are
    # screen-perspective, not user-perspective.
    if cheek_a[0] <= cheek_b[0]:
        left_cheek, right_cheek = cheek_a, cheek_b
    else:
        left_cheek, right_cheek = cheek_b, cheek_a

    landmarks = {
        "forehead": pt(ZONE_INDICES["forehead"]),
        "tzone": pt(ZONE_INDICES["tzone"]),
        "left_cheek": left_cheek,
        "right_cheek": right_cheek,
        "chin": pt(ZONE_INDICES["chin"]),
    }

    return {
        "found": True,
        "bbox": bbox,
        "contour": contour,
        "landmarks": landmarks,
        # Original photo dimensions in pixels — the mobile renderer needs
        # these to apply the BoxFit.cover transform without having to
        # re-fetch and decode the JPEG itself.
        "image_size": [int(bgr.shape[1]), int(bgr.shape[0])],
    }


@app.get("/health")
def health() -> dict:
    return {"ok": True, "service": "face-mesh"}


@app.post("/detect")
async def detect(request: Request) -> JSONResponse:
    """Accepts raw image bytes in the request body (any Content-Type) and
    returns face geometry. Multipart not supported intentionally — the
    Dart backend posts raw bytes."""
    data = await request.body()
    if not data:
        raise HTTPException(status_code=400, detail="empty_body")
    if len(data) > 25 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="image_too_large")

    bgr = _read_image(data)
    result = _detect(bgr)
    if result is None:
        return JSONResponse({"found": False, "reason": "no_face"})
    return JSONResponse(result)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "app:app",
        host="0.0.0.0",
        port=int(os.getenv("PORT", "8000")),
        workers=1,
    )
