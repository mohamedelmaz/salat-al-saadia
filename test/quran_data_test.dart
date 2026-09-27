// Tests for the Quran data layer: the global Ayah numbering (which drives both
// the Ayah markers and the CDN URLs), the verse cache, and the recitation-URL
// builders' refusal to produce a URL the CDN does not serve.
//
// These run without a device, a network connection or a GPS fix.
//
//   flutter test test/quran_data_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:salat_al_saadia/features/quran/data/quran_data.dart';

void main() {
  group('QuranRepository.globalAyahNumber', () {
    // The prefix-sum table replaced an O(n) loop that ran once per Ayah on
    // every rebuild; these lock the numbers down so the optimisation cannot
    // silently change the Ayah markers or the CDN URLs.
    test('numbers the Ayahs continuously from 1 to 6236', () {
      final QuranRepository repository = QuranRepository();
      int expected = 0;
      for (int surah = 1; surah <= repository.totalSurahCount; surah++) {
        final int count = repository.verseCountOf(surah);
        for (int verse = 1; verse <= count; verse++) {
          expected++;
          expect(
            repository.globalAyahNumber(surah, verse),
            expected,
            reason: 'Surah $surah, Ayah $verse',
          );
        }
      }
      expect(expected, 6236);
    });

    test('is stable across calls (memoised, not recomputed)', () {
      final QuranRepository repository = QuranRepository();
      final int first = repository.globalAyahNumber(2, 255);
      expect(repository.globalAyahNumber(2, 255), first);
      // Al-Baqarah 2:255 is Ayah 262 of the mushaf (Al-Fatihah's 7 Ayahs
      // precede it), and the exhaustive 1..6236 walk above already proved the
      // whole mapping.
      expect(first, 262);
    });

    test('clamps out-of-range input instead of building a dead URL', () {
      final QuranRepository repository = QuranRepository();
      // Ayah 0 clamps up to Ayah 1 of the same Surah.
      expect(
        repository.globalAyahNumber(1, 0),
        repository.globalAyahNumber(1, 1),
      );
      // A Surah past 114 clamps to An-Nas, not to an out-of-bounds index.
      expect(
        repository.globalAyahNumber(999, 1),
        repository.globalAyahNumber(114, 1),
      );
      // An Ayah past the end of the Surah clamps to its last Ayah.
      expect(
        repository.globalAyahNumber(1, 500),
        repository.globalAyahNumber(1, 7),
      );
    });
  });

  group('QuranRepository.versesOf', () {
    test('returns one entry per Ayah and caches both variants', () {
      final QuranRepository repository = QuranRepository();
      final List<String> withSymbols = repository.versesOf(1);
      expect(withSymbols, hasLength(7)); // Al-Fatihah

      // The two variants must not collide in the cache (the cache key encodes
      // the `withVerseEndSymbol` flag).
      final List<String> withoutSymbols =
          repository.versesOf(1, withVerseEndSymbol: false);
      expect(withoutSymbols, hasLength(7));
      expect(withoutSymbols, isNot(equals(withSymbols)));
      // Second read comes from the cache and must be identical.
      expect(repository.versesOf(1), same(withSymbols));
    });

    test('exposes the 114 Surahs with sane metadata', () {
      final QuranRepository repository = QuranRepository();
      expect(repository.totalSurahCount, 114);
      expect(repository.surahs, hasLength(114));
      expect(repository.surah(1)?.arabicName, isNotEmpty);
      expect(repository.surah(0), isNull);
      expect(repository.surah(115), isNull);
      // Al-Fatihah is the only Surah whose Basmala *is* Ayah 1, and At-Tawbah
      // has none — both are excluded from the header.
      expect(repository.showsBasmalaHeader(1), isFalse);
      expect(repository.showsBasmalaHeader(9), isFalse);
      expect(repository.showsBasmalaHeader(2), isTrue);
    });
  });

  group('recitation URLs', () {
    test('return null for a reciter that lacks that layout', () {
      final QuranRepository repository = QuranRepository();
      // Al-Husary is single-Ayah only; Al-Basit Murattal is whole-Surah only.
      expect(
        repository.recitationUrlForSurah(1, QuranReciter.husary),
        isNull,
      );
      expect(
        repository.recitationUrlForVerse(
            1, 1, QuranReciter.abdulBasitMurattal),
        isNull,
      );
    });

    test('build the documented CDN paths when the layout is supported', () {
      final QuranRepository repository = QuranRepository();
      expect(
        repository.recitationUrlForSurah(114, QuranReciter.alafasy),
        'https://cdn.islamic.network/quran/audio-surah/128/ar.alafasy/114.mp3',
      );
      // Single Ayahs are addressed by the global Ayah number: 2:1 is Ayah 8.
      expect(
        repository.recitationUrlForVerse(2, 1, QuranReciter.alafasy),
        'https://cdn.islamic.network/quran/audio/128/ar.alafasy/8.mp3',
      );
    });

    test('the offered reciters never disagree with the URL builders', () {
      final QuranRepository repository = QuranRepository();
      for (final QuranReciter reciter in QuranReciter.forSurah()) {
        expect(repository.recitationUrlForSurah(1, reciter), isNotNull);
      }
      for (final QuranReciter reciter in QuranReciter.forVerse()) {
        expect(repository.recitationUrlForVerse(1, 1, reciter), isNotNull);
      }
      expect(QuranReciter.forSurah(), isNotEmpty);
      expect(QuranReciter.forVerse(), isNotEmpty);
    });
  });
}