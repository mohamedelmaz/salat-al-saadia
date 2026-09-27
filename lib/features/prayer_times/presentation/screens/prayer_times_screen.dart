import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../controllers/prayer_times_controller.dart';

/// Today's prayer timetable, computed with `adhan` from the device's real
/// position (with a documented Cairo fallback when no GPS fix is available).
///
/// The previous version of this screen was hard-coded mock data: the same six
/// fake times, a hard-coded "الصلاة القادمة: الظهر" and a frozen
/// "01:42:15" countdown that never changed. Nothing here is mocked any more.
class PrayerTimesScreen extends ConsumerWidget {
  const PrayerTimesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PrayerTimesState state = ref.watch(prayerTimesProvider);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('مواقيت الصلاة'),
        actions: <Widget>[
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh),
            onPressed: state.loading
                ? null
                : () => ref.read(prayerTimesProvider.notifier).refresh(),
          ),
        ],
      ),
      body: switch (state) {
        final PrayerTimesState s when s.loading && s.slots.isEmpty =>
          _buildLoading(isDark),
        final PrayerTimesState s when s.slots.isEmpty => _buildNoData(isDark),
        final PrayerTimesState s => _buildTimetable(context, ref, s, isDark),
      },
    );
  }

  Widget _buildLoading(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox.square(
            dimension: 44,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: AppColors.secondaryGold,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'جارٍ تحديد موقعك وحساب المواقيت…',
            style: GoogleFonts.cairo(
              fontSize: 14,
              color: isDark ? Colors.white70 : AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoData(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'تعذر حساب المواقيت. يرجى المحاولة مرة أخرى.',
          textAlign: TextAlign.center,
          style: GoogleFonts.cairo(
            fontSize: 15,
            color: isDark ? Colors.white70 : AppColors.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildTimetable(
    BuildContext context,
    WidgetRef ref,
    PrayerTimesState state,
    bool isDark,
  ) {
    final DateTime now = DateTime.now();
    final AppPrayer? next = state.nextPrayer;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        _buildNextPrayerBanner(state, next, isDark),
        if (state.errorMessage != null) _buildWarning(state, isDark),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: _buildPresetSelector(context, ref, state, isDark),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            elevation: 0,
            color: isDark ? AppColors.cardSurfaceDark : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: <Widget>[
                for (int i = 0; i < state.slots.length; i++) ...<Widget>[
                  if (i > 0) const Divider(height: 1),
                  _buildSlotRow(state.slots[i], now, isDark),
                ],
              ],
            ),
          ),
        ),
        if (state.usingFallbackLocation)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
            child: Text(
              'تعذّر تحديد موقعك، لذلك تُعرض مواقيت القاهرة. امنح إذن الموقع '
              'أو فعّل GPS ثم اضغط تحديث.',
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: 12,
                height: 1.6,
                color: isDark ? Colors.white54 : AppColors.textMuted,
              ),
            ),
          ),
      ],
    );
  }

  /// Gradient banner: next prayer name + live HH:MM:SS countdown.
  Widget _buildNextPrayerBanner(
    PrayerTimesState state,
    AppPrayer? next,
    bool isDark,
  ) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[
            AppColors.primaryEmeraldDark,
            AppColors.primaryEmeraldLight,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.primaryEmerald.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                next == null ? 'الصلاة القادمة' : 'الصلاة القادمة: ${next.label}',
                style: GoogleFonts.cairo(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Icon(Icons.notifications_active,
                  color: AppColors.secondaryGold),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _formatRemaining(state.remaining),
            style: GoogleFonts.cairo(
              color: AppColors.secondaryGold,
              fontSize: 38,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          Text(
            'متبقي على رفع الأذان',
            style: GoogleFonts.cairo(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  /// Non-blocking banner for a permission problem (the timetable still renders).
  Widget _buildWarning(PrayerTimesState state, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color:
            AppColors.secondaryGold.withValues(alpha: isDark ? 0.16 : 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.secondaryGold.withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.warning_amber, size: 20, color: AppColors.goldDark),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              state.errorMessage!,
              style: GoogleFonts.cairo(
                fontSize: 12.5,
                height: 1.5,
                color: isDark ? Colors.white70 : AppColors.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Calculation-convention dropdown.
  Widget _buildPresetSelector(
    BuildContext context,
    WidgetRef ref,
    PrayerTimesState state,
    bool isDark,
  ) {
    return Row(
      children: <Widget>[
        const Icon(Icons.settings_outlined,
            size: 18, color: AppColors.primaryEmeraldLight),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'طريقة الحساب: ${state.preset.label}',
            style: GoogleFonts.cairo(
              fontSize: 12.5,
              color: isDark ? Colors.white70 : AppColors.textMuted,
            ),
          ),
        ),
        PopupMenuButton<CalculationPreset>(
          tooltip: 'طريقة الحساب',
          icon:
              const Icon(Icons.expand_more, color: AppColors.primaryEmerald),
          onSelected: (CalculationPreset preset) =>
              ref.read(prayerTimesProvider.notifier).setPreset(preset),
          itemBuilder: (BuildContext context) => CalculationPreset.values
              .map(
                (CalculationPreset preset) =>
                    PopupMenuItem<CalculationPreset>(
                  value: preset,
                  child:
                      Text(preset.label, style: GoogleFonts.cairo(fontSize: 13)),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  /// One timetable row: name on the right, time on the left, the next prayer
  /// highlighted in gold.
  Widget _buildSlotRow(PrayerSlot slot, DateTime now, bool isDark) {
    final bool isNext = slot.isNext;
    final bool passed = slot.isPassed(now);

    return ListTile(
      tileColor: isNext
          ? AppColors.secondaryGold.withValues(alpha: 0.12)
          : null,
      leading: Icon(
        Icons.access_time_filled,
        color: isNext
            ? AppColors.secondaryGold
            : (passed ? AppColors.textMuted : AppColors.primaryEmerald),
      ),
      title: Text(
        slot.prayer.label,
        style: GoogleFonts.cairo(
          fontWeight: isNext ? FontWeight.bold : FontWeight.normal,
          color: isNext
              ? AppColors.secondaryGold
              : (isDark ? Colors.white : AppColors.textDark),
        ),
      ),
      trailing: Text(
        _formatTimeOfDay(slot.time),
        style: GoogleFonts.cairo(
          fontWeight: isNext ? FontWeight.w600 : FontWeight.normal,
          color: isNext ? AppColors.secondaryGold : AppColors.textMuted,
        ),
      ),
    );
  }

  /// 24-hour `HH:MM` — unambiguous across locales, unlike `12:28 PM` inside an
  /// Arabic RTL layout.
  static String _formatTimeOfDay(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  /// `HH:MM:SS` countdown, clamped at zero.
  static String _formatRemaining(Duration duration) {
    final int hours = duration.inHours;
    final int minutes = duration.inMinutes.remainder(60);
    final int seconds = duration.inSeconds.remainder(60);
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}
