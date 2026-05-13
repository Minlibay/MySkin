# App icon renderer

Renders the "Моя Кожа" app icon (Direction A — Italic Monogram, per
`design/App Icon.html`) into every size required by iOS and Android,
including the Android adaptive-icon foreground/background pair.

## One-shot

```bash
mkdir -p tools/icons/fonts
curl -sSL -o tools/icons/fonts/CormorantGaramond-MediumItalic.ttf \
  "https://fonts.gstatic.com/s/cormorantgaramond/v21/co3smX5slCNuHLi8bLeY9MK7whWMhyjYrGFEsdtdc62E6zd5wDDOjw.ttf"
curl -sSL -o tools/icons/fonts/JetBrainsMono-Regular.ttf \
  "https://github.com/JetBrains/JetBrainsMono/raw/master/fonts/ttf/JetBrainsMono-Regular.ttf"
python tools/icons/render_icons.py
```

Outputs:

- `assets/branding/app_icon{,_foreground,_background}.png` — 1024 masters
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png` — 15 sizes
- `android/app/src/main/res/mipmap-*/ic_launcher{,_round}.png` — legacy
- `android/app/src/main/res/mipmap-*/ic_launcher_{foreground,background}.png` — adaptive layers
- `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher{,_round}.xml` — adaptive XML

Requires Python with Pillow.
