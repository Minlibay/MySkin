"""Generate splash-screen logo assets from the existing app icon foreground.
Drops a transparent М-centered PNG into the iOS LaunchImage.imageset and the
Android drawable folder so both launch screens can render the brand mark on a
flat blush background defined by their respective theme files.
"""

from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "assets" / "branding" / "app_icon_foreground.png"


def export(path: Path, size: int):
    path.parent.mkdir(parents=True, exist_ok=True)
    img = Image.open(SRC).convert("RGBA")
    img = img.resize((size, size), Image.LANCZOS)
    img.save(path, "PNG")
    print(f"  {path.relative_to(ROOT)}  {size}x{size}")


def main():
    print("iOS LaunchImage.imageset:")
    ios = ROOT / "ios" / "Runner" / "Assets.xcassets" / "LaunchImage.imageset"
    # Apple's LaunchScreen.storyboard centers the image with no resizing,
    # so 1x/2x/3x point sizes 200/400/600 yield a comfortably sized monogram.
    export(ios / "LaunchImage.png", 200)
    export(ios / "LaunchImage@2x.png", 400)
    export(ios / "LaunchImage@3x.png", 600)

    print("Android drawable:")
    drawable = ROOT / "android" / "app" / "src" / "main" / "res" / "drawable"
    export(drawable / "splash_logo.png", 480)

    print("Done.")


if __name__ == "__main__":
    main()
