import 'package:quran/quran.dart' as quran;

/// Metadata for one Surah, resolved from the offline `quran` dataset.
class SurahInfo {
  const SurahInfo({
    required this.number,
    required this.arabicName,
    required this.englishName,
    required this.versesCount,
    required this.isMakkah,
  });

  /// Builds the metadata straight from the bundled Uthmani mushaf data.
  factory SurahInfo.fromNumber(int number) {
    final String place = quran.getPlaceOfRevelation(number);
    return SurahInfo(
      number: number,
      arabicName: quran.getSurahNameArabic(number),
      englishName: quran.getSurahNameEnglish(number),
      versesCount: quran.getVerseCount(number),
      isMakkah: place.toLowerCase().startsWith('makka'),
    );
  }

  final int number;
  final String arabicName;
  final String englishName;
  final int versesCount;
  final bool isMakkah;

  /// "مكية" / "مدنية"
  String get revelationLabel => isMakkah ? 'مكية' : 'مدنية';

  /// "مكية • 7 آيات"
  String get subtitle =>
      '$revelationLabel • $versesCount ${versesCount == 1 ? 'آية' : 'آيات'}';
}
