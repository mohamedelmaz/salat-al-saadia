import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Loads the Quranic typeface at start-up.
///
/// Rendering the Uthmani script properly needs a Naskh typeface with real
/// Arabic shaping and tashkeel positioning — the platform default font mangles
/// the vowels on several Android builds. Two free options are used, in order of
/// preference:
///
/// 1. **Bundled asset** (fully offline, recommended): drop any of the files
///    listed in [bundledFontAssets] into `assets/fonts/`. The first one that is
///    present is registered at start-up and wins. See
///    `assets/fonts/README.md` for the download links (King Fahd Complex
///    "KFGQPC Uthman Taha Naskh" and the OFL-licensed "Amiri Quran").
/// 2. **Google Fonts "Amiri Quran"** (SIL OFL): used by
///    [AppTypography.quranStyle] when no bundled file exists. `google_fonts`
///    caches the downloaded font, so it keeps working offline afterwards.
///
/// Nothing here can crash the app: if neither option is available the text
/// simply falls back to the platform Arabic font (still correct, just less
/// beautiful).
class QuranFonts {
  QuranFonts._();

  /// Family name the bundled font is registered under.
  static const String family = 'UthmanTahaNaskh';

  /// Candidate font files, in order of preference. The first file that exists
  /// in the bundle is used.
  static const List<String> bundledFontAssets = <String>[
    'assets/fonts/UthmanTahaNaskh-Regular.ttf',
    'assets/fonts/AmiriQuran-Regular.ttf',
    'assets/fonts/Amiri-Regular.ttf',
  ];

  static bool _bundledFamilyLoaded = false;
  static bool _attempted = false;

  /// `true` once a bundled font has been registered with the engine.
  static bool get isBundledFamilyLoaded => _bundledFamilyLoaded;

  /// Registers the bundled Quran font if it is present. Safe to call more than
  /// once; call it from `main()` before `runApp()` so the first frame already
  /// uses the right typeface.
  static Future<void> ensureLoaded() async {
    if (_attempted) return;
    _attempted = true;

    for (final String asset in bundledFontAssets) {
      try {
        final ByteData data = await rootBundle.load(asset);
        final FontLoader loader = FontLoader(family)
          ..addFont(Future<ByteData>.value(data));
        await loader.load();
        _bundledFamilyLoaded = true;
        if (kDebugMode) {
          debugPrint('QuranFonts: registered "$family" from $asset');
        }
        return;
      } catch (_) {
        // Asset not shipped (the default) — try the next candidate. Note that
        // `rootBundle.load` on a missing asset throws a `FlutterError`, which
        // is not an `Exception`, hence the catch-all.
      }
    }

    if (kDebugMode) {
      debugPrint(
        'QuranFonts: no bundled Quran font found in assets/fonts/ — '
        'falling back to Google Fonts "Amiri Quran".',
      );
    }
  }
}
