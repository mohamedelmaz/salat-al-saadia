import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quran/quran.dart' as quran;

import 'surah_info.dart';

export 'surah_info.dart';

/// Reciters offered by the free Islamic Network CDN (the same host the `quran`
/// package's audio helpers point at).
///
/// Availability was verified with HTTP `HEAD` requests: the CDN does not serve
/// every edition in both the "whole Surah" and the "single Ayah" layout, so the
/// UI only offers editions that really respond with `200` for the mode in use.
enum QuranReciter {
  /// 200 for both layouts.
  alafasy('ar.alafasy', 'مشاري راشد العفاسي',
      surahAudio: true, verseAudio: true),

  /// 200 for the whole-Surah layout only.
  abdulBasitMurattal(
    'ar.abdulbasitmurattal',
    'عبد الباسط عبد الصمد (مرتل)',
    surahAudio: true,
    verseAudio: false,
  ),

  /// 200 for the single-Ayah layout only.
  husary('ar.husary', 'محمود خليل الحصري', surahAudio: false, verseAudio: true);

  const QuranReciter(
    this.id,
    this.arabicName, {
    required this.surahAudio,
    required this.verseAudio,
  });

  /// CDN edition id, e.g. `ar.alafasy`.
  final String id;
  final String arabicName;
  final bool surahAudio;
  final bool verseAudio;

  /// Reciters that can be used for a whole Surah.
  static List<QuranReciter> forSurah() => QuranReciter.values
      .where((QuranReciter reciter) => reciter.surahAudio)
      .toList(growable: false);

  /// Reciters that can be used for a single Ayah.
  static List<QuranReciter> forVerse() => QuranReciter.values
      .where((QuranReciter reciter) => reciter.verseAudio)
      .toList(growable: false);
}

/// All Quran reads go through this repository so the raw `quran` package stays
/// swappable, the dataset lookups can be memoised, and the recitation URLs have
/// a single source of truth.
class QuranRepository {
  QuranRepository();

  List<SurahInfo>? _surahIndex;
  final Map<int, List<String>> _verseCache = <int, List<String>>{};

  /// `ayahOffset[surah]` = number of Ayahs that come *before* `surah`, so the
  /// global Ayah number of (surah, verse) is `ayahOffset[surah] + verse`.
  ///
  /// Built once, lazily. The previous implementation summed
  /// `getVerseCount(1..surah-1)` on *every* call, and the mushaf reader calls it
  /// once per Ayah on every rebuild — ~32 000 `getVerseCount` lookups for
  /// Al-Baqarah alone, repeated on each font-size change.
  List<int>? _ayahOffset;

  List<int> get _offsets {
    final List<int>? cached = _ayahOffset;
    if (cached != null) return cached;

    final List<int> offsets = List<int>.filled(quran.totalSurahCount + 2, 0);
    int running = 0;
    for (int surah = 1; surah <= quran.totalSurahCount; surah++) {
      offsets[surah] = running;
      running += quran.getVerseCount(surah);
    }
    // Sanity guard: the Hafs narration has exactly 6236 Ayahs. If a future
    // version of the dataset ever disagrees, fall back to the slow path instead
    // of silently returning wrong numbers.
    if (running != quran.totalVerseCount) {
      for (int surah = 1; surah <= quran.totalSurahCount; surah++) {
        offsets[surah] = 0;
        for (int earlier = 1; earlier < surah; earlier++) {
          offsets[surah] += quran.getVerseCount(earlier);
        }
      }
    }
    return _ayahOffset = offsets;
  }

  /// Every Surah of the mushaf (1 → 114).
  List<SurahInfo> get surahs {
    return _surahIndex ??= List<SurahInfo>.generate(
      quran.totalSurahCount,
      (int index) => SurahInfo.fromNumber(index + 1),
      growable: false,
    );
  }

  /// Surah metadata by number, or `null` when out of range.
  SurahInfo? surah(int number) {
    if (number < 1 || number > quran.totalSurahCount) return null;
    return surahs[number - 1];
  }

  /// The Ayahs of a Surah, in Uthmani script.
  ///
  /// [withVerseEndSymbol] appends the authentic end-of-ayah marker
  /// (۝ + Arabic-Indic numeral). Results are cached per Surah, because
  /// `quran.getVerse` rescans the whole dataset for every single Ayah.
  List<String> versesOf(int surahNumber, {bool withVerseEndSymbol = true}) {
    final int cacheKey = surahNumber * 2 + (withVerseEndSymbol ? 0 : 1);
    final List<String>? cached = _verseCache[cacheKey];
    if (cached != null) return cached;

    final int count = quran.getVerseCount(surahNumber);
    final List<String> verses = List<String>.generate(
      count,
      (int index) => quran.getVerse(
        surahNumber,
        index + 1,
        verseEndSymbol: withVerseEndSymbol,
      ),
      growable: false,
    );

    _verseCache[cacheKey] = verses;
    return verses;
  }

  /// The Basmala, as it appears at the head of every Surah except At-Tawbah.
  String get basmala => quran.basmala;

  /// At-Tawbah (9) has no Basmala, and in Al-Fatihah it *is* the first Ayah.
  bool showsBasmalaHeader(int surahNumber) =>
      surahNumber != 1 && surahNumber != 9;

  /// Recitation URL for a whole Surah, or `null` when [reciter] has no
  /// whole-Surah edition on the CDN (see [QuranReciter.surahAudio]).
  ///
  /// Returning `null` lets the caller show a real explanation instead of
  /// firing a request that is guaranteed to 404.
  String? recitationUrlForSurah(int surahNumber, QuranReciter reciter) {
    if (!reciter.surahAudio) return null;
    return 'https://cdn.islamic.network/quran/audio-surah/128/'
        '${reciter.id}/$surahNumber.mp3';
  }

  /// Recitation URL for a single Ayah, or `null` when [reciter] has no
  /// single-Ayah edition on the CDN (see [QuranReciter.verseAudio]).
  ///
  /// The CDN addresses Ayahs by their global number (1 → 6236), so the
  /// Surah/Ayah pair is converted first.
  String? recitationUrlForVerse(
    int surahNumber,
    int verseNumber,
    QuranReciter reciter,
  ) {
    if (!reciter.verseAudio) return null;
    return 'https://cdn.islamic.network/quran/audio/128/'
        '${reciter.id}/${globalAyahNumber(surahNumber, verseNumber)}.mp3';
  }

  /// Number of Ayahs in a Surah.
  int verseCountOf(int surahNumber) => quran.getVerseCount(surahNumber);

  /// `true` when the Ayah is one of the Sajdah Ayahs.
  bool isSajdahVerse(int surahNumber, int verseNumber) =>
      quran.isSajdahVerse(surahNumber, verseNumber);

  /// Total number of Ayahs in the mushaf (6236 for the Hafs narration).
  int get totalVerseCount => quran.totalVerseCount;

  /// Total number of Surahs (114).
  int get totalSurahCount => quran.totalSurahCount;

  /// Global Ayah number (1-6236) used by the recitation CDN and by the Ayah
  /// markers printed in the mushaf.
  ///
  /// O(1) after the first call (see [_offsets]); out-of-range input is clamped
  /// to the valid mushaf range so a bad index can never produce a URL for a
  /// non-existent track.
  int globalAyahNumber(int surahNumber, int verseNumber) {
    final int surah =
        surahNumber.clamp(1, quran.totalSurahCount).toInt();
    final int verse = verseNumber.clamp(
      1,
      quran.getVerseCount(surah),
    ).toInt();
    return _offsets[surah] + verse;
  }
}

final Provider<QuranRepository> quranRepositoryProvider =
    Provider<QuranRepository>((Ref ref) => QuranRepository());

/// The 114 Surahs, ready for the index list.
final Provider<List<SurahInfo>> surahIndexProvider = Provider<List<SurahInfo>>(
  (Ref ref) => ref.watch(quranRepositoryProvider).surahs,
);

/// Ayahs of one Surah, end-of-ayah markers included.
final ProviderFamily<List<String>, int> surahVersesProvider =
    Provider.family<List<String>, int>(
  (Ref ref, int surahNumber) =>
      ref.watch(quranRepositoryProvider).versesOf(surahNumber),
);

/// User-selected reciter (shared by the Surah-list "play" buttons and the
/// player bar).
final StateProvider<QuranReciter> quranReciterProvider =
    StateProvider<QuranReciter>((Ref ref) => QuranReciter.alafasy);

/// Font size of the mushaf text, adjustable from the Surah screen (A- / A+).
final StateProvider<double> quranFontSizeProvider =
    StateProvider<double>((Ref ref) => 26.0);
