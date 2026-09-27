import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../data/quran_audio_player.dart';
import '../../data/quran_data.dart';
import '../widgets/quran_audio_bar.dart';
import 'surah_screen.dart';

/// Filter query of the Surah index, kept in a provider so typing survives
/// rebuilds of the tab.
final StateProvider<String> surahSearchQueryProvider =
    StateProvider<String>((Ref ref) => '');

/// The Quran tab: a searchable index of all 114 Surahs with a per-Surah
/// play button, plus entry into the mushaf reader.
class QuranScreen extends ConsumerWidget {
  const QuranScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String query = ref.watch(surahSearchQueryProvider).trim();
    final List<SurahInfo> surahs = ref.watch(surahIndexProvider);

    final List<SurahInfo> filtered = query.isEmpty
        ? surahs
        : surahs
            .where((SurahInfo surah) =>
                surah.arabicName.contains(query) ||
                surah.englishName.toLowerCase().contains(query.toLowerCase()) ||
                surah.number.toString() == query)
            .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('القرآن الكريم'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              onChanged: (String value) =>
                  ref.read(surahSearchQueryProvider.notifier).state = value,
              style: GoogleFonts.cairo(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'ابحث عن سورة بالاسم أو رقمها…',
                hintStyle:
                    GoogleFonts.cairo(color: AppColors.textMuted, fontSize: 13),
                prefixIcon:
                    const Icon(Icons.search, color: AppColors.textMuted),
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.cardSurfaceDark
                    : Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'لا توجد نتائج لـ "$query"',
                      style: GoogleFonts.cairo(
                          fontSize: 15, color: AppColors.textMuted),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: AppColors.textMuted.withValues(alpha: 0.12)),
                    itemBuilder: (BuildContext context, int index) {
                      return _SurahTile(surah: filtered[index]);
                    },
                  ),
          ),
          const QuranAudioBar(),
        ],
      ),
    );
  }
}

class _SurahTile extends ConsumerWidget {
  const _SurahTile({required this.surah});

  final SurahInfo surah;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final QuranAudioState audio = ref.watch(quranAudioProvider);
    final bool isCurrent =
        audio.surahNumber == surah.number && !audio.isVersePlayback;

    return Material(
      color: isCurrent
          ? AppColors.secondaryGold.withValues(alpha: 0.08)
          : Colors.transparent,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
              builder: (_) => SurahScreen(surahNumber: surah.number)),
        ),
        leading: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primaryEmerald.withValues(alpha: 0.10),
            border: Border.all(
                color: AppColors.secondaryGold.withValues(alpha: 0.5)),
          ),
          child: Text(
            '${surah.number}',
            style: GoogleFonts.cairo(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryEmerald,
            ),
          ),
        ),
        title: Text(
          'سورة ${surah.arabicName}',
          style: GoogleFonts.cairo(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : AppColors.textDark,
          ),
        ),
        subtitle: Text(
          surah.subtitle,
          style: GoogleFonts.cairo(fontSize: 12, color: AppColors.textMuted),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              surah.englishName,
              style:
                  GoogleFonts.cairo(fontSize: 10, color: AppColors.textMuted),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip:
                  isCurrent && audio.isPlaying ? 'إيقاف مؤقت' : 'تشغيل السورة',
              icon: isCurrent && audio.isBusy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.secondaryGold),
                    )
                  : Icon(
                      isCurrent && audio.isPlaying
                          ? Icons.pause_circle
                          : Icons.play_circle,
                      color: AppColors.secondaryGold,
                      size: 34,
                    ),
              onPressed: () {
                if (isCurrent) {
                  ref.read(quranAudioProvider.notifier).togglePlayPause();
                } else {
                  ref.read(quranAudioProvider.notifier).playSurah(surah.number);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
