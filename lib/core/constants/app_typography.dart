import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../fonts/quran_fonts.dart';

class AppTypography {
  /// Family registered by `google_fonts` for the OFL "Amiri Quran" typeface.
  /// Used as a fallback when no font is bundled in `assets/fonts/`.
  static const String googleQuranFamily = 'Amiri Quran';

  /// Style for Quranic text (Ayahs, Basmala, Surah headers).
  ///
  /// Uses the bundled Uthmanic Naskh font when available, otherwise
  /// `google_fonts`' "Amiri Quran", otherwise the platform Arabic font.
  /// Always render Quranic text inside a `Directionality`/`textDirection: rtl`
  /// context so the ayah markers (۝) and diacritics are positioned correctly.
  static TextStyle quranStyle({
    double fontSize = 26,
    FontWeight fontWeight = FontWeight.normal,
    Color? color,
    double height = 2.1,
  }) {
    if (QuranFonts.isBundledFamilyLoaded) {
      return TextStyle(
        fontFamily: QuranFonts.family,
        fontFamilyFallback: const <String>[
          googleQuranFamily,
          'Amiri',
          'Noto Naskh Arabic'
        ],
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
      );
    }
    return GoogleFonts.amiriQuran(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
    );
  }

  /// Style for decorative Quranic headings (Surah names, Basmala band).
  static TextStyle quranHeadingStyle({
    double fontSize = 22,
    FontWeight fontWeight = FontWeight.bold,
    Color? color,
  }) {
    if (QuranFonts.isBundledFamilyLoaded) {
      return TextStyle(
        fontFamily: QuranFonts.family,
        fontFamilyFallback: const <String>[googleQuranFamily, 'Amiri'],
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
      );
    }
    return GoogleFonts.amiri(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
    );
  }

  /// UI Standard Font (Cairo)
  static TextStyle uiStyle({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.normal,
    Color? color,
  }) {
    return GoogleFonts.cairo(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
    );
  }
}
