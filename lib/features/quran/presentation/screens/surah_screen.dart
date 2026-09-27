import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../data/quran_audio_player.dart';
import '../../data/quran_data.dart';
import '../widgets/quran_audio_bar.dart';

/// Mushaf reader for one Surah: full Uthmani text with an ornamental header,
/// tap an Ayah marker to play that Ayah, adjustable font size (A- / A+) and
/// the persistent [QuranAudioBar] pinned to the bottom.
class SurahScreen extends ConsumerWidget {
  const SurahScreen({super.key, required this.surahNumber});

  final int surahNumber;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final QuranRepository repository = ref.watch(quranRepositoryProvider);
    final SurahInfo? surah = repository.surah(surahNumber);
    if (surah == null) {
      return const Scaffold(body: Center(child: Text('سورة غير موجودة')));
    }

    final List<String> verses = ref.watch(surahVersesProvider(surahNumber));
    final double fontSize = ref.watch(quranFontSizeProvider);
    final QuranAudioState audio = ref.watch(quranAudioProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('سورة ${surah.arabicName}'),
        actions: <Widget>[
          IconButton(
            tooltip: 'تصغير الخط',
            icon: const Icon(Icons.text_decrease),
            onPressed: fontSize > 18
                ? () => ref.read(quranFontSizeProvider.notifier).state =
                    fontSize - 2
                : null,
          ),
          IconButton(
            tooltip: 'تكبير الخط',
            icon: const Icon(Icons.text_increase),
            onPressed: fontSize < 48
                ? () => ref.read(quranFontSizeProvider.notifier).state =
                    fontSize + 2
                : null,
          ),
          PopupMenuButton<QuranReciter>(
            tooltip: 'اختيار القارئ',
            icon: const Icon(Icons.record_voice_over_outlined),
            onSelected: (QuranReciter reciter) =>
                ref.read(quranAudioProvider.notifier).selectReciter(reciter),
            // Mode-aware: while an Ayah is playing only the editions the CDN
            // serves in the single-Ayah layout may be offered, otherwise the
            // user could pick one and get a 404.
            itemBuilder: (BuildContext context) => (audio.isVersePlayback
                    ? QuranReciter.forVerse()
                    : QuranReciter.forSurah())
                .map(
                  (QuranReciter reciter) => PopupMenuItem<QuranReciter>(
                    value: reciter,
                    child: Text(reciter.arabicName,
                        style: GoogleFonts.cairo(fontSize: 13)),
                  ),
                )
                .toList(),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: <Widget>[
                Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryEmerald.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: AppColors.secondaryGold.withValues(alpha: 0.6)),
                  ),
                  child: Column(
                    children: <Widget>[
                      Text(
                        'سورة ${surah.arabicName}',
                        style: AppTypography.quranHeadingStyle(fontSize: 24),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${surah.revelationLabel} • ${surah.versesCount} آية',
                        style: GoogleFonts.cairo(
                            fontSize: 11, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                if (repository.showsBasmalaHeader(surahNumber))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      repository.basmala,
                      style: AppTypography.quranStyle(
                          fontSize: fontSize, height: 1.6),
                      textAlign: TextAlign.center,
                    ),
                  ),
                Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      // Each Ayah is followed by its own number marker, mushaf
                      // style. The previous version emitted *every* marker first
                      // and then the whole text, so the reader showed a row of
                      // circles above the Surah instead of markers between the
                      // Ayahs.
                      for (int i = 0; i < verses.length; i++) ...<InlineSpan>[
                        TextSpan(text: '${verses[i]} '),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: _AyahMarker(
                            number: repository.globalAyahNumber(
                              surahNumber,
                              i + 1,
                            ),
                            active: audio.isVersePlayback &&
                                audio.surahNumber == surahNumber &&
                                audio.verseNumber == i + 1,
                            onTap: () => ref
                                .read(quranAudioProvider.notifier)
                                .playVerse(surahNumber, i + 1),
                          ),
                        ),
                      ],
                    ],
                  ),
                  style: AppTypography.quranStyle(fontSize: fontSize),
                  textAlign: TextAlign.justify,
                  textDirection: TextDirection.rtl,
                ),
              ],
            ),
          ),
          const QuranAudioBar(),
        ],
      ),
    );
  }
}

/// Round Ayah-number marker rendered inline between Ayahs; tapping it starts
/// ayah-by-ayah playback from that Ayah.
class _AyahMarker extends StatelessWidget {
  const _AyahMarker(
      {required this.number, required this.active, required this.onTap});

  final int number;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active
              ? AppColors.secondaryGold.withValues(alpha: 0.35)
              : AppColors.secondaryGold.withValues(alpha: 0.12),
          border:
              Border.all(color: AppColors.secondaryGold.withValues(alpha: 0.7)),
        ),
        child: Text(
          '$number',
          style: GoogleFonts.cairo(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: AppColors.primaryEmerald,
          ),
        ),
      ),
    );
  }
}
