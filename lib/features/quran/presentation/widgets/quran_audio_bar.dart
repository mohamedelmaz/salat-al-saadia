import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../data/quran_audio_player.dart';
import '../../data/quran_data.dart';

/// Mini player shown at the bottom of the Quran screens while a recitation is
/// loaded.
///
/// It is the visible half of the audio fix: a real play/pause control, a
/// buffering spinner, a seek bar, playback speed, Ayah repeat and — most
/// importantly — a SnackBar whenever `just_audio` reports a failure, instead of
/// a button that silently does nothing.
class QuranAudioBar extends ConsumerWidget {
  const QuranAudioBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final QuranAudioState state = ref.watch(quranAudioProvider);
    final QuranAudioController controller =
        ref.read(quranAudioProvider.notifier);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    ref.listen<QuranAudioState>(quranAudioProvider,
        (QuranAudioState? previous, QuranAudioState next) {
      final String? message = next.errorMessage;
      if (message == null || message == previous?.errorMessage) return;

      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(message, style: GoogleFonts.cairo(fontSize: 13)),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'إخفاء',
            textColor: Colors.white,
            onPressed: controller.acknowledgeError,
          ),
        ),
      );
      controller.acknowledgeError();
    });

    if (!state.hasTrack) return const SizedBox.shrink();

    final String surahName = ref
            .watch(quranRepositoryProvider)
            .surah(state.surahNumber!)
            ?.arabicName ??
        '';
    final String title = state.isVersePlayback
        ? 'سورة $surahName • الآية ${state.verseNumber}'
        : 'سورة $surahName كاملة';

    return Material(
      color: isDark ? AppColors.cardSurfaceDark : Colors.white,
      elevation: 12,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  _LeadingStatus(state: state),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.cairo(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : AppColors.textDark,
                          ),
                        ),
                        Text(
                          'القارئ: ${state.reciter.arabicName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.cairo(
                              fontSize: 11, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  _SpeedButton(
                      speed: state.speed, onSelected: controller.setSpeed),
                  _ReciterButton(
                      state: state, onSelected: controller.selectReciter),
                  IconButton(
                    tooltip: 'إيقاف',
                    onPressed: controller.stop,
                    icon: const Icon(Icons.close),
                    color: AppColors.textMuted,
                  ),
                ],
              ),
              _SeekBar(state: state, onSeek: controller.seek),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  IconButton(
                    tooltip: state.isVersePlayback
                        ? 'الآية السابقة'
                        : 'السورة السابقة',
                    onPressed: controller.skipPrevious,
                    icon: const Icon(Icons.skip_previous),
                    color: AppColors.primaryEmerald,
                  ),
                  _PlayPauseButton(
                      state: state, onPressed: controller.togglePlayPause),
                  IconButton(
                    tooltip: state.isVersePlayback
                        ? 'الآية التالية'
                        : 'السورة التالية',
                    onPressed: controller.skipNext,
                    icon: const Icon(Icons.skip_next),
                    color: AppColors.primaryEmerald,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: state.repeatCurrent
                        ? 'إلغاء تكرار الآية'
                        : 'تكرار الآية الحالية',
                    onPressed: controller.toggleRepeat,
                    icon: Icon(
                        state.repeatCurrent ? Icons.repeat_on : Icons.repeat),
                    color: state.repeatCurrent
                        ? AppColors.secondaryGold
                        : AppColors.textMuted,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeadingStatus extends StatelessWidget {
  const _LeadingStatus({required this.state});

  final QuranAudioState state;

  @override
  Widget build(BuildContext context) {
    if (state.isBusy) {
      return const SizedBox(
        width: 40,
        height: 40,
        child: Padding(
          padding: EdgeInsets.all(9),
          child: CircularProgressIndicator(
              strokeWidth: 2.5, color: AppColors.secondaryGold),
        ),
      );
    }

    final IconData icon = state.hasFailed
        ? Icons.error_outline
        : (state.isPlaying ? Icons.graphic_eq : Icons.music_note);
    final Color color =
        state.hasFailed ? Colors.red.shade600 : AppColors.secondaryGold;

    return CircleAvatar(
      radius: 20,
      backgroundColor: color.withValues(alpha: 0.12),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({required this.state, required this.onPressed});

  final QuranAudioState state;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (state.isBusy) {
      return Container(
        width: 52,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.primaryEmerald.withValues(alpha: 0.12),
        ),
        child: const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
              strokeWidth: 2.5, color: AppColors.primaryEmerald),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
          shape: BoxShape.circle, color: AppColors.primaryEmerald),
      child: IconButton(
        tooltip: state.isPlaying ? 'إيقاف مؤقت' : 'تشغيل',
        onPressed: onPressed,
        iconSize: 28,
        color: AppColors.secondaryGold,
        icon: Icon(state.isPlaying ? Icons.pause : Icons.play_arrow),
      ),
    );
  }
}

class _SeekBar extends StatelessWidget {
  const _SeekBar({required this.state, required this.onSeek});

  final QuranAudioState state;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    final Duration total = state.duration ?? Duration.zero;
    final double max =
        total.inMilliseconds <= 0 ? 1 : total.inMilliseconds.toDouble();
    final double value = state.position.inMilliseconds.clamp(0, max).toDouble();

    return Row(
      children: <Widget>[
        Text(_formatDuration(state.position), style: _timeStyle),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2.5,
              activeTrackColor: AppColors.secondaryGold,
              inactiveTrackColor: AppColors.textMuted.withValues(alpha: 0.25),
              thumbColor: AppColors.secondaryGold,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: value,
              max: max,
              onChanged: total > Duration.zero
                  ? (double milliseconds) =>
                      onSeek(Duration(milliseconds: milliseconds.round()))
                  : null,
            ),
          ),
        ),
        Text(_formatDuration(total), style: _timeStyle),
      ],
    );
  }

  TextStyle get _timeStyle => GoogleFonts.cairo(
        fontSize: 10,
        color: AppColors.textMuted,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      );
}

class _SpeedButton extends StatelessWidget {
  const _SpeedButton({required this.speed, required this.onSelected});

  final double speed;
  final ValueChanged<double> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<double>(
      tooltip: 'سرعة التلاوة',
      initialValue: speed,
      onSelected: onSelected,
      itemBuilder: (BuildContext context) => const <double>[
        0.75,
        1.0,
        1.25,
        1.5,
        2.0
      ]
          .map((double value) =>
              PopupMenuItem<double>(value: value, child: Text('$value×')))
          .toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Text(
          '$speed×',
          style: GoogleFonts.cairo(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: AppColors.primaryEmerald,
          ),
        ),
      ),
    );
  }
}

class _ReciterButton extends StatelessWidget {
  const _ReciterButton({required this.state, required this.onSelected});

  final QuranAudioState state;
  final ValueChanged<QuranReciter> onSelected;

  @override
  Widget build(BuildContext context) {
    // The CDN does not serve every edition in both layouts, so only the
    // reciters that work for the current playback mode are offered.
    final List<QuranReciter> options = state.isVersePlayback
        ? QuranReciter.forVerse()
        : QuranReciter.forSurah();

    return PopupMenuButton<QuranReciter>(
      tooltip: 'اختيار القارئ',
      icon: const Icon(Icons.record_voice_over_outlined,
          color: AppColors.primaryEmerald),
      onSelected: onSelected,
      itemBuilder: (BuildContext context) => options
          .map(
            (QuranReciter reciter) => PopupMenuItem<QuranReciter>(
              value: reciter,
              child: Text(reciter.arabicName,
                  style: GoogleFonts.cairo(fontSize: 13)),
            ),
          )
          .toList(),
    );
  }
}

String _formatDuration(Duration duration) {
  final int minutes = duration.inMinutes;
  final String seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
