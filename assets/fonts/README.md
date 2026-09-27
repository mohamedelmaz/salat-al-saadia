# Arabic / Quranic fonts

`QuranFonts.ensureLoaded()` (called from `main()`) registers the **first** file it
finds in this folder, in this order:

1. `UthmanTahaNaskh-Regular.ttf`
2. `AmiriQuran-Regular.ttf`
3. `Amiri-Regular.ttf`

Drop one of them here and it is used for all Quranic text (Ayahs, Basmala, Surah
headers) with no code change. If none is present the app falls back to Google
Fonts "Amiri Quran" (SIL OFL, cached after the first download) and, failing that,
to the platform Arabic font.

Free sources:

- **KFGQPC Uthman Taha Naskh** (King Fahd Complex) —
  <https://fonts.qurancomplex.gov.sa/> — the typeface the printed Madinah mushaf
  uses; free to use and redistribute for non-commercial Quranic publishing.
- **Amiri Quran** (SIL OFL) — <https://fonts.google.com/specimen/Amiri+Quran>
- **Amiri** (SIL OFL) — <https://fonts.google.com/specimen/Amiri>

> This folder is listed under `flutter.assets` in `pubspec.yaml`, so any font
> dropped in here is bundled into the APK automatically.
