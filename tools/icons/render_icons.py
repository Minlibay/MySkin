"""Render Моя Кожа app icon (Direction A — Italic Monogram) at all required sizes
for iOS and Android, from the spec in design/App Icon.html.

Source of truth: spec values
  canvas      1024 x 1024
  background  linear 135deg #FCEEF2 -> #F8E8EE @55% -> #F5DCE4
  glow        circle cx=512 cy=450 r=380, white 35%, blur 40px
  letter      M (Cyrillic), Cormorant Garamond Medium Italic, 700px,
              fill oklch(0.42 0.11 12) ~ sRGB(125,46,61), baseline y=640
  hairline    (380,780)-(644,780), wine 40%, 2px
  caption     "КОЖА" JetBrains Mono 38px, tracking 12, wine 60%, anchor (512,820)
"""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
FONTS = Path(__file__).resolve().parent / "fonts"
CORMORANT = str(FONTS / "CormorantGaramond-MediumItalic.ttf")
JBMONO = str(FONTS / "JetBrainsMono-Regular.ttf")

WINE = (125, 46, 61)
BG_STOPS = [
    (0.00, (252, 238, 242)),
    (0.55, (248, 232, 238)),
    (1.00, (245, 220, 228)),
]


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def stop_color(t):
    for i in range(len(BG_STOPS) - 1):
        p0, c0 = BG_STOPS[i]
        p1, c1 = BG_STOPS[i + 1]
        if p0 <= t <= p1:
            local = (t - p0) / (p1 - p0) if p1 > p0 else 0.0
            return lerp(c0, c1, local)
    return BG_STOPS[-1][1]


def make_background(size):
    # Render at low res for speed, then upscale — gradient is smooth.
    small = 256
    img = Image.new("RGBA", (small, small))
    px = img.load()
    for y in range(small):
        for x in range(small):
            t = (x + y) / (2 * (small - 1))
            px[x, y] = stop_color(t) + (255,)
    return img.resize((size, size), Image.LANCZOS)


def make_glow(size):
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    s = size / 1024
    cx, cy, r = int(512 * s), int(450 * s), int(380 * s)
    ImageDraw.Draw(layer).ellipse(
        (cx - r, cy - r, cx + r, cy + r),
        fill=(255, 255, 255, int(0.35 * 255)),
    )
    return layer.filter(ImageFilter.GaussianBlur(max(1, int(40 * s))))


def draw_content(layer, size):
    s = size / 1024
    d = ImageDraw.Draw(layer)

    cormorant = ImageFont.truetype(CORMORANT, int(round(700 * s)))
    d.text((512 * s, 640 * s), "М", font=cormorant, fill=WINE, anchor="ms")

    hair_w = max(1, int(round(2 * s)))
    d.line(
        [(380 * s, 780 * s), (644 * s, 780 * s)],
        fill=WINE + (int(0.4 * 255),),
        width=hair_w,
    )

    mono = ImageFont.truetype(JBMONO, int(round(38 * s)))
    text = "КОЖА"
    spacing = 12 * s
    widths = [mono.getlength(ch) for ch in text]
    total = sum(widths) + spacing * (len(text) - 1)
    x = 512 * s - total / 2
    fill = WINE + (int(0.6 * 255),)
    for ch, w in zip(text, widths):
        d.text((x, 820 * s), ch, font=mono, fill=fill, anchor="ls")
        x += w + spacing


def compose(size, background=True, content=True):
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    if background:
        out = Image.alpha_composite(out, make_background(size))
        out = Image.alpha_composite(out, make_glow(size))
    if content:
        layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        draw_content(layer, size)
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
