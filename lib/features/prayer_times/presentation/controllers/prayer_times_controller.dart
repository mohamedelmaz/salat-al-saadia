import 'dart:async';

import 'package:adhan/adhan.dart' as adhan;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/location/location_access.dart';

/// The calculation conventions offered in the UI.
enum CalculationPreset {
  /// Egyptian General Authority of Survey — the official method in Egypt,
  /// Saudi Arabia and most of the Arab world.
  egyptian('الهيئة المصرية العامة للمساحة', adhan.CalculationMethod.egyptian),

  /// Umm al-Qura University, Makkah.
  ummAlQura('جامعة أم القرى، مكة', adhan.CalculationMethod.umm_al_qura),

  /// Muslim World League.
  muslimWorldLeague(
      'رابطة العالم الإسلامي', adhan.CalculationMethod.muslim_world_league),

  /// University of Islamic Sciences, Karachi.
  karachi('جامعة العلوم الإسلامية، كراتشي', adhan.CalculationMethod.karachi),

  /// ISNA — North America.
  northAmerica('الجمعية الإسلامية لأمريكا الشمالية',
      adhan.CalculationMethod.north_america);

  const CalculationPreset(this.label, this.method);

  final String label;
  final adhan.CalculationMethod method;
}

/// The prayers shown in the timetable, in order. [AppPrayer.sunrise] is
/// included because worshippers need it, but it is never the "current" prayer
/// and never becomes the countdown target.
enum AppPrayer {
  fajr('الفجر', adhan.Prayer.fajr),
  sunrise('الشروق', adhan.Prayer.sunrise),
  dhuhr('الظهر', adhan.Prayer.dhuhr),
  asr('العصر', adhan.Prayer.asr),
  maghrib('المغرب', adhan.Prayer.maghrib),
  isha('العشاء', adhan.Prayer.isha);

  const AppPrayer(this.label, this.prayer);

  final String label;
  final adhan.Prayer prayer;

  /// Sunrise is a reference time, not a prayer: it is excluded from the
  /// current/next logic so the countdown never stops at sunrise.
  bool get isPrayer => this != AppPrayer.sunrise;
}

/// One row of the timetable.
class PrayerSlot {
  const PrayerSlot({
    required this.prayer,
    required this.time,
    required this.isNext,
  });

  final AppPrayer prayer;

  /// Local wall-clock time of this prayer today.
  final DateTime time;

  /// `true` for the single prayer the countdown is aiming at.
  final bool isNext;

  /// `true` once the time has passed (or is "now").
  bool isPassed(DateTime now) => !time.isAfter(now);
}

/// Everything the prayer-times screen renders.
class PrayerTimesState {
  const PrayerTimesState({
    this.loading = true,
    this.slots = const <PrayerSlot>[],
    this.nextPrayer,
    this.nextTime,
    this.remaining = Duration.zero,
    this.locationLabel,
    this.errorMessage,
    this.preset = CalculationPreset.egyptian,
    this.usingFallbackLocation = false,
  });

  final bool loading;
  final List<PrayerSlot> slots;

  /// The prayer the countdown is aiming at (never sunrise).
  final AppPrayer? nextPrayer;
  final DateTime? nextTime;
  final Duration remaining;

  /// Human-readable place, when available.
  final String? locationLabel;

  /// Arabic, user-facing reason the timetable could not be produced.
  final String? errorMessage;

  final CalculationPreset preset;

  /// `true` when the coordinates are the hard-coded fallback (no GPS fix).
  final bool usingFallbackLocation;

  bool get hasError => errorMessage != null;

  PrayerTimesState copyWith({
    bool? loading,
    List<PrayerSlot>? slots,
    Object? nextPrayer = _unset,
    Object? nextTime = _unset,
    Duration? remaining,
    Object? locationLabel = _unset,
    Object? errorMessage = _unset,
    CalculationPreset? preset,
    bool? usingFallbackLocation,
  }) {
    return PrayerTimesState(
      loading: loading ?? this.loading,
      slots: slots ?? this.slots,
      nextPrayer: identical(nextPrayer, _unset)
          ? this.nextPrayer
          : nextPrayer as AppPrayer?,
      nextTime: identical(nextTime, _unset)
          ? this.nextTime
          : nextTime as DateTime?,
      remaining: remaining ?? this.remaining,
      locationLabel: identical(locationLabel, _unset)
          ? this.locationLabel
          : locationLabel as String?,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      preset: preset ?? this.preset,
      usingFallbackLocation:
          usingFallbackLocation ?? this.usingFallbackLocation,
    );
  }

  static const Object _unset = Object();
}

/// Coordinates used when no GPS fix is available. Cairo — the app's origin —
/// so the user still sees a coherent timetable instead of an error screen.
/// (`Coordinates` is not a const constructor, hence `final`.)
final adhan.Coordinates _fallbackCoordinates =
    adhan.Coordinates(30.0444, 31.2357, validate: true);

/// Loads today's prayer times and keeps the countdown ticking.
///
/// Design notes:
/// * The timetable is computed once per day and cached; only the countdown is
///   recomputed on each tick, so six prayer rows are not rebuilt every second.
/// * When the date rolls over (the app was left open overnight) the timetable
///   is recomputed automatically.
/// * The ticker is always cancelled in `ref.onDispose`; nothing else owns it.
class PrayerTimesNotifier extends Notifier<PrayerTimesState> {
  Timer? _ticker;

  /// Date the cached slots belong to (midnight of that day).
  DateTime? _cachedForDate;

  adhan.Coordinates _coordinates = _fallbackCoordinates;

  /// Set when the provider is disposed, so the in-flight `refresh()` and the
  /// periodic ticker can never write to a dead notifier.
  bool _disposed = false;

  @override
  PrayerTimesState build() {
    ref.onDispose(() {
      _disposed = true;
      _ticker?.cancel();
    });
    // Kick off the first load; the screen shows its spinner meanwhile.
    Future<void>.microtask(refresh);
    return const PrayerTimesState();
  }

  /// Calculation convention chosen by the user.
  void setPreset(CalculationPreset preset) {
    if (preset == state.preset) return;
    state = state.copyWith(preset: preset, loading: true);
    _cachedForDate = null;
    unawaited(refresh());
  }

  /// Re-reads the position and rebuilds the timetable.
  Future<void> refresh() async {
    state = state.copyWith(loading: true, errorMessage: null);

    final LocationAccessResult access =
        await LocationAccess.ensureAccess();
    // `Notifier`'s `ref` exposes no `mounted` flag, so a local disposed-guard
    // (set in `build`'s `onDispose`) is used to avoid writing `state` after
    // the provider was torn down.
    if (_disposed) return;

    final position = access.position;
    if (position != null) {
      _coordinates = adhan.Coordinates(
        position.latitude,
        position.longitude,
        validate: true,
      );
    } else {
      // No fix: keep a usable timetable instead of showing nothing.
      _coordinates = _fallbackCoordinates;
    }

    _recompute();
    state = state.copyWith(
      loading: false,
      usingFallbackLocation: position == null,
      // A permission problem is worth surfacing; a bare GPS timeout is not,
      // because the fallback timetable is still coherent.
      errorMessage: access.isGranted ? null : access.message,
    );
    _ensureTicker();
  }

  /// Recomputes today's timetable and restarts the countdown.
  ///
  /// `adhan`'s solar maths produces `NaN` inside the polar circles, where the
  /// sun can stay below the horizon all day (or above it all night) and no
  /// Fajr/Isha twilight exists. It then throws from `TimeComponents`. The app
  /// must survive that: the user is told the calculation is unavailable for
  /// their location instead of getting a red error screen or a crash.
  void _recompute() {
    try {
      _recomputeUnsafe();
    } catch (error) {
      _ticker?.cancel();
      state = state.copyWith(
        loading: false,
        slots: const <PrayerSlot>[],
        nextPrayer: null,
        nextTime: null,
        remaining: Duration.zero,
        errorMessage: 'تعذّر حساب المواقيت في هذه المنطقة جغرافياً '
            '(خط عرض مرتفع جداً). يمكنك اختيار طريقة حساب أخرى.',
      );
      if (kDebugMode) {
        debugPrint('PrayerTimesNotifier: calculation failed -> $error');
      }
    }
  }

  void _recomputeUnsafe() {
    final DateTime now = DateTime.now();
    final adhan.CalculationParameters params = state.preset.method.getParameters()
      ..madhab = adhan.Madhab.shafi
      ..highLatitudeRule = adhan.HighLatitudeRule.middle_of_the_night;

    // The `PrayerTimes` factory takes (coordinates, dateComponents, params)
    // and resolves to *device-local* times, so no manual timezone conversion
    // is needed anywhere in this file.
    final adhan.PrayerTimes today = adhan.PrayerTimes(
      _coordinates,
      adhan.DateComponents.from(now),
      params,
    );

    final Map<AppPrayer, DateTime> byPrayer = <AppPrayer, DateTime>{
      for (final AppPrayer slot in AppPrayer.values)
        slot: today.timeForPrayer(slot.prayer)!,
    };

    // The "next" prayer is the earliest *prayer* (sunrise excluded) still ahead.
    AppPrayer? next;
    DateTime? nextTime;
    for (final AppPrayer candidate in AppPrayer.values) {
      if (!candidate.isPrayer) continue;
      final DateTime time = byPrayer[candidate]!;
      if (time.isAfter(now)) {
        next = candidate;
        nextTime = time;
        break;
      }
    }

    // Between Isha and midnight every prayer is in the past: aim at tomorrow's
    // Fajr instead of showing an empty countdown for the whole pre-dawn hour.
    if (next == null) {
      final adhan.PrayerTimes tomorrow = adhan.PrayerTimes(
        _coordinates,
        adhan.DateComponents(
          now.year,
          now.month,
          now.day + 1,
        ),
        params,
      );
      next = AppPrayer.fajr;
      nextTime = tomorrow.fajr;
    }

    final DateTime midnight = DateTime(now.year, now.month, now.day);
    _cachedForDate = midnight;

    state = state.copyWith(
      slots: <PrayerSlot>[
        for (final AppPrayer slot in AppPrayer.values)
          PrayerSlot(
            prayer: slot,
            time: byPrayer[slot]!,
            isNext: slot == next,
          ),
      ],
      nextPrayer: next,
      nextTime: nextTime,
      remaining: _remainingUntil(now, nextTime),
    );
  }

  static Duration _remainingUntil(DateTime now, DateTime? target) {
    if (target == null) return Duration.zero;
    final Duration remaining = target.difference(now);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  void _ensureTicker() {
    _ticker?.cancel();
    // 1 Hz: smooth enough for an HH:MM:SS readout without rebuilding the
    // widget tree more often than a human can read it.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed) return;
      final DateTime now = DateTime.now();

      // Midnight rollover: the cached timetable belongs to yesterday.
      final DateTime? cached = _cachedForDate;
      if (cached != null &&
          (now.year != cached.year ||
              now.month != cached.month ||
              now.day != cached.day)) {
        _recompute();
        return;
      }

      // The target was reached (or passed): advance "current/next" once,
      // otherwise just tick the seconds.
      final DateTime? target = state.nextTime;
      if (target == null || !target.isAfter(now)) {
        _recompute();
        return;
      }

      state = state.copyWith(remaining: _remainingUntil(now, target));
    });
  }
}

final NotifierProvider<PrayerTimesNotifier, PrayerTimesState>
    prayerTimesProvider =
    NotifierProvider<PrayerTimesNotifier, PrayerTimesState>(
  PrayerTimesNotifier.new,
);
