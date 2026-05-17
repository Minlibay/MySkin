"""Render MySkin app icon (v2 — Italic Monogram, Premium) at all required sizes
for iOS and Android.

Composition (1024×1024 canvas):
  background  radial gradient centered (520, 460), inner #FFF4F6 →
              outer #E8C3CE, with corner vignette #C7889A @8%
  petal arc   single thin wine crescent behind the letter, 5% opacity,
              evokes a flower petal / skin contour without being literal
  letter      Latin "M", Cormorant Garamond Medium Italic, 760px,
              vertical gradient #7D2E3D (top) → #B06378 (bottom),
              anchor centered at (512, 600)
  sheen       diagonal white sheen across upper-left of the M, 9% white,
              masked by the M's alpha so it only shows on the glyph
  shadow      micro-shadow behind the M, 4px y-offset, 6% wine

No caption, no hairline. Launcher labels the app "MySkin" below the icon
on both platforms — repeating it inside the icon is visual noise and
illegible at home-screen size.

Source font:
  tools/icons/fonts/CormorantGaramond-MediumItalic.ttf
"""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops

ROOT = Path(__file__).resolve().parents[2]
FONTS = Path(__file__).resolve().parent / "fonts"
CORMORANT = str(FONTS / "CormorantGaramond-MediumItalic.ttf")

WINE_DEEP = (110, 38, 54)     # #6E2636 — letter top, slightly deeper
WINE_SOFT = (188, 116, 134)   # #BC7486 — letter bottom (premium rose)

BG_INNER = (255, 247, 249)    # #FFF7F9 — highlight tone
BG_OUTER = (224, 184, 196)    # #E0B8C4 — outer rose
VIGNETTE = (185, 122, 142)    # #B97A8E — subtle corner darkening

# Italic shear added on top of the font's own slope. Cormorant Garamond
# Medium Italic renders almost upright in Pillow, so we synthesise extra
# slant here. -0.13 ≈ 7.4° lean to the right — refined, not aggressive.
ITALIC_SHEAR = -0.13


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def make_background(size):
    """Radial gradient with highlight shifted to upper-left so it doesn't
    sit behind the letter (which gave a 'smudge' look in v2). Plus a soft
    corner vignette for depth."""
    small = 256
    img = Image.new("RGB", (small, small))
    px = img.load()
    # Light source from the upper-left quadrant
    cx, cy = int(0.36 * small), int(0.30 * small)
    max_r = ((small - cx) ** 2 + (small - cy) ** 2) ** 0.5
    corner_max_r = (small ** 2 + small ** 2) ** 0.5 / 2
    for y in range(small):
        for x in range(small):
            dx, dy = x - cx, y - cy
            r = (dx * dx + dy * dy) ** 0.5
            t = min(1.0, r / max_r)
            t = 1 - (1 - t) ** 1.6
            base = lerp(BG_INNER, BG_OUTER, t)
            corner_r = ((x - small / 2) ** 2 + (y - small / 2) ** 2) ** 0.5
            v = max(0.0, (corner_r / corner_max_r - 0.65) / 0.35) * 0.12
            base = lerp(base, VIGNETTE, v)
            px[x, y] = base
    return img.convert("RGBA").resize((size, size), Image.LANCZOS)


def make_petal_arc(size):
    """Thin wine arc sweeping behind the letter from upper-right down
    along its right edge. Reads as a single petal contour, not a disc.
    Subtle by design — should whisper, not announce itself."""
    s = size / 1024
    # Big ellipse, slightly off the canvas to the lower-right, so only its
    # upper-left rim crosses the icon's interior.
    outer = Image.new("L", (size, size), 0)
    ImageDraw.Draw(outer).ellipse(
        (int(120 * s), int(60 * s), int(1180 * s), int(1120 * s)),
        fill=255,
    )
    # Inner ellipse very close to outer → thin crescent rim
    inner = Image.new("L", (size, size), 0)
    ImageDraw.Draw(inner).ellipse(
        (int(80 * s), int(20 * s), int(1140 * s), int(1080 * s)),
        fill=255,
    )
    crescent = ImageChops.subtract(outer, inner)
    crescent = crescent.filter(ImageFilter.GaussianBlur(int(10 * s)))

    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    tint = Image.new("RGBA", (size, size), WINE_DEEP + (int(0.07 * 255),))
    layer.paste(tint, (0, 0), crescent)
    return layer


def make_letter_layer(size, with_shadow=True):
    """Italic M with vertical gradient fill, a strong diagonal sheen, and a
    micro-shadow. Synthesises extra italic lean via affine shear on top of
    the font's own slope."""
    s = size / 1024
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    # 1. Letter alpha mask, then shear it to add visible italic lean. We
    #    render in an oversized canvas so the slant doesn't clip on the
    #    right side, then trim back to the icon size.
    font_size = int(round(740 * s))
    font = ImageFont.truetype(CORMORANT, font_size)
    pad = int(200 * s)
    big = Image.new("L", (size + 2 * pad, size + 2 * pad), 0)
    ImageDraw.Draw(big).text(
        (int(512 * s) + pad, int(560 * s) + pad), "M",
        font=font, fill=255, anchor="mm",
    )
    # Affine: x' = x + ITALIC_SHEAR * (y - y_center). PIL's Image.AFFINE
    # consumes (a, b, c, d, e, f) for the inverse mapping
    #   x_src = a*x_dst + b*y_dst + c
    #   y_src = d*x_dst + e*y_dst + f
    # so we use the inverse of the desired skew (sign flipped).
    y_center = (size / 2) + pad
    sheared = big.transform(
        big.size, Image.AFFINE,
        (1, -ITALIC_SHEAR, ITALIC_SHEAR * y_center, 0, 1, 0),
        resample=Image.BICUBIC,
    )
    letter_mask = sheared.crop((pad, pad, pad + size, pad + size))

    # 2. Vertical gradient (deep wine top → premium rose bottom). Build a
    #    1×size column then stretch — same result, way faster.
    col = Image.new("RGBA", (1, size))
    cpx = col.load()
    for y in range(size):
        t = y / (size - 1)
        cpx[0, y] = lerp(WINE_DEEP, WINE_SOFT, t) + (255,)
    grad = col.resize((size, size), Image.NEAREST)

    # 3. Micro-shadow — soft, low opacity, slight y-offset
    if with_shadow:
        shadow = letter_mask.filter(
            ImageFilter.GaussianBlur(max(2, int(9 * s))))
        shadow_layer = Image.new("RGBA", (size, size),
                                 WINE_DEEP + (int(0.08 * 255),))
        offset_shadow = Image.new("L", (size, size), 0)
        offset_shadow.paste(shadow, (0, int(round(6 * s))))
        layer.paste(shadow_layer, (0, 0), offset_shadow)

    # 4. Gradient-filled letter
    layer.paste(grad, (0, 0), letter_mask)

    # 5. Diagonal sheen — tighter, brighter band across the upper-left
    #    portion of the M. Acts as a glass highlight.
    sheen_mask = Image.new("L", (size, size), 0)
    spx = sheen_mask.load()
    # Sweep direction: about 35° from vertical, descending right→left
    nx, ny = 0.574, -0.819   # cos 35°, -sin 35°
    band_center_x, band_center_y = 360 * s, 280 * s
    half_width = 70 * s
    peak = 0.32
    for y in range(size):
        for x in range(size):
            d = (x - band_center_x) * nx + (y - band_center_y) * ny
            v = max(0.0, 1 - abs(d) / half_width)
            # smoothstep for softer edges
            v = v * v * (3 - 2 * v)
            spx[x, y] = int(v * 255 * peak)
    # Soften the sheen edges
    sheen_mask = sheen_mask.filter(ImageFilter.GaussianBlur(int(4 * s)))
    # Intersect sheen with letter so highlight only paints on the glyph
    combined = ImageChops.multiply(
        sheen_mask, letter_mask.point(lambda v: v),
    )
    sheen_layer = Image.new("RGBA", (size, size), (255, 255, 255, 255))
    layer.paste(sheen_layer, (0, 0), combined)

    return layer


def compose(size, background=True, content=True):
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    if background:
        out = Image.alpha_composite(out, make_background(size))
        out = Image.alpha_composite(out, make_petal_arc(size))
    if content:
        # On adaptive foreground (no background), the shadow would land on
        # transparency and look broken once Android composes its own bg
        # behind. Keep shadow only when we have our own background.
        layer = make_letter_layer(size, with_shadow=background)
        out = Image.alpha_composite(out, layer)
    return out


def save_resized(master, out_path, size):
    out_path.parent.mkdir(parents=True, exist_ok=True)
    master.resize((size, size), Image.LANCZOS).save(out_path, "PNG")
    print(f"  {out_path.relative_to(ROOT)}  {size}x{size}")


def circular(img, size):
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, size, size), fill=255)
    out.paste(img.resize((size, size), Image.LANCZOS), (0, 0), mask)
    return out


def main():
    print("Master 1024...")
    master = compose(1024, background=True, content=True)
    fg = compose(1024, background=False, content=True)
    bg = compose(1024, background=True, content=False)

    branding = ROOT / "assets" / "branding"
    branding.mkdir(parents=True, exist_ok=True)
    master.save(branding / "app_icon.png", "PNG")
    fg.save(branding / "app_icon_foreground.png", "PNG")
    bg.save(branding / "app_icon_background.png", "PNG")
    print(f"  assets/branding/app_icon{{,_foreground,_background}}.png")

    ios_set = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    ios_files = {
        "Icon-App-20x20@1x.png": 20, "Icon-App-20x20@2x.png": 40, "Icon-App-20x20@3x.png": 60,
        "Icon-App-29x29@1x.png": 29, "Icon-App-29x29@2x.png": 58, "Icon-App-29x29@3x.png": 87,
        "Icon-App-40x40@1x.png": 40, "Icon-App-40x40@2x.png": 80, "Icon-App-40x40@3x.png": 120,
        "Icon-App-60x60@2x.png": 120, "Icon-App-60x60@3x.png": 180,
        "Icon-App-76x76@1x.png": 76, "Icon-App-76x76@2x.png": 152,
        "Icon-App-83.5x83.5@2x.png": 167,
        "Icon-App-1024x1024@1x.png": 1024,
    }
    print("iOS:")
    for name, size in ios_files.items():
        save_resized(master, ios_set / name, size)

    android_res = ROOT / "android" / "app" / "src" / "main" / "res"
    legacy = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    print("Android legacy:")
    for density, size in legacy.items():
        save_resized(master, android_res / f"mipmap-{density}" / "ic_launcher.png", size)
        round_path = android_res / f"mipmap-{density}" / "ic_launcher_round.png"
        round_path.parent.mkdir(parents=True, exist_ok=True)
        circular(master, size).save(round_path, "PNG")
        print(f"  {round_path.relative_to(ROOT)}  {size}x{size} (round)")

    print("Android adaptive (108dp foreground + background):")
    adaptive = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
    for density, size in adaptive.items():
        save_resized(fg, android_res / f"mipmap-{density}" / "ic_launcher_foreground.png", size)
        save_resized(bg, android_res / f"mipmap-{density}" / "ic_launcher_background.png", size)

    anydpi = android_res / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    xml = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@mipmap/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '</adaptive-icon>\n'
    )
    (anydpi / "ic_launcher.xml").write_text(xml, encoding="utf-8")
    (anydpi / "ic_launcher_round.xml").write_text(xml, encoding="utf-8")
    print("  mipmap-anydpi-v26/ic_launcher{,_round}.xml")

    print("Done.")


if __name__ == "__main__":
    main()
