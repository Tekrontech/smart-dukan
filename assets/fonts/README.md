# Fonts (spec Section 4)

Fonts are bundled in the app, never downloaded at runtime. Put these TTF
files in this folder, then uncomment the `fonts:` block in `pubspec.yaml`.

| File | Source |
|---|---|
| Inter-Regular.ttf, Inter-Medium.ttf, Inter-SemiBold.ttf, Inter-Bold.ttf | https://fonts.google.com/specimen/Inter (Download family → `static/` folder) |
| NotoNastaliqUrdu-Regular.ttf, NotoNastaliqUrdu-Bold.ttf | https://fonts.google.com/noto/specimen/Noto+Nastaliq+Urdu |
| NotoNaskhArabic-Regular.ttf, NotoNaskhArabic-Bold.ttf | https://fonts.google.com/noto/specimen/Noto+Naskh+Arabic |

All three are under the SIL Open Font License — keep each `OFL.txt` here.

To keep the APK small (target under 30 MB), use the static weights listed
above, not the variable font files.
