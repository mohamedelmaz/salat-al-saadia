// Tests for the prayer-times maths (`adhan`) behind the timetable screen.
//
// These verify the calculation layer only — no GPS, no permission dialog, no
// timer. The screen's own countdown/ticker logic needs a live `Timer`, so it is
// covered manually rather than here.
//
//   flutter test test/prayer_times_test.dart

import 'package:adhan/adhan.dart' as adhan;
import 'package:flutter_test/flutter_test.dart';
import 'package:salat_al_saadia/features/prayer_times/presentation/controllers/prayer_times_controller.dart';

/// The parameter set the app actually uses for a preset.
adhan.CalculationParameters _params(CalculationPreset preset) =>
    preset.method.getParameters()
      ..madhab = adhan.Madhab.shafi
      ..highLatitudeRule = adhan.HighLatitudeRule.middle_of_the_night;

void main() {
  group('AppPrayer', () {
    test('excludes sunrise from the current/next logic', () {
      // Sunrise is shown in the timetable but must never be the countdown
      // target, otherwise the banner would stop at sunrise every morning.
      expect(AppPrayer.values, hasLength(6));
      expect(AppPrayer.sunrise.isPrayer, isFalse);
      expect(AppPrayer.values.where((AppPrayer p) => p.isPrayer), hasLength(5));
    });

    test('every prayer maps to a real adhan prayer with an Arabic label', () {
      for (final AppPrayer prayer in AppPrayer.values) {
        expect(prayer.label, isNotEmpty);
        expect(prayer.prayer, isNot(adhan.Prayer.none));
      }
    });
  });

  group('PrayerTimesState', () {
    // `nextPrayer`/`nextTime`/`errorMessage` are nullable, so `copyWith` uses a
    // sentinel to be able to *clear* them (a plain `??` could never do that).
    test('omitting a field leaves it unchanged', () {
      const PrayerTimesState base = PrayerTimesState(
        loading: false,
        nextPrayer: AppPrayer.asr,
        errorMessage: 'boom',
      );
      final PrayerTimesState next = base.copyWith(loading: true);
      expect(next.loading, isTrue);
      expect(next.nextPrayer, AppPrayer.asr);
      expect(next.errorMessage, 'boom');
    });

    test('starts empty and defaults to the Egyptian method', () {
      const PrayerTimesState base = PrayerTimesState();
      expect(base.loading, isTrue);
      expect(base.slots, isEmpty);
      expect(base.nextPrayer, isNull);
      expect(base.usingFallbackLocation, isFalse);
      expect(base.hasError, isFalse);
      expect(base.preset, CalculationPreset.egyptian);
    });
  });

  group('adhan calculation (the prayer-times maths)', () {
    test('produces a coherent, correctly ordered Cairo timetable', () {
      final adhan.PrayerTimes times = adhan.PrayerTimes(
        adhan.Coordinates(30.0444, 31.2357),
        adhan.DateComponents(2024, 6, 21),
        _params(CalculationPreset.egyptian),
      );

      // Order must always be fajr < sunrise < dhuhr < asr < maghrib < isha.
      expect(times.fajr.isBefore(times.sunrise), isTrue);
      expect(times.sunrise.isBefore(times.dhuhr), isTrue);
      expect(times.dhuhr.isBefore(times.asr), isTrue);
      expect(times.asr.isBefore(times.maghrib), isTrue);
      expect(times.maghrib.isBefore(times.isha), isTrue);

      // Cairo in late June. `adhan` resolves to *device-local* times, so the
      // absolute hour depends on the test host's timezone — only the ordering
      // and the sunrise<dhuhr<sunset spacing are environment-independent.
      // (Verified against Cairo local time: sunrise ≈ 04:55, maghrib ≈ 19:02.)
      expect(
        times.maghrib.difference(times.sunrise).inHours,
        inInclusiveRange(13, 15),
      );
    });

    test('every preset yields six times and a near-identical dhuhr', () {
      // Dhuhr is pure solar transit: it barely depends on the Fajr/Isha angles.
      // It is not *exactly* identical across presets, though — most methods add
      // a +1 minute safety offset to Dhuhr while Umm al-Qura (which uses an
      // Isha interval) adds none — so the assertion allows that 1-minute band.
      DateTime? referenceDhuhr;
      for (final CalculationPreset preset in CalculationPreset.values) {
        final adhan.PrayerTimes times = adhan.PrayerTimes(
          adhan.Coordinates(51.5074, -0.1278), // London
          adhan.DateComponents(2024, 12, 21),
          _params(preset),
        );
        expect(times.timeForPrayer(adhan.Prayer.none), isNull);
        for (final AppPrayer prayer in AppPrayer.values) {
          expect(times.timeForPrayer(prayer.prayer), isNotNull,
              reason: '${prayer.label} missing for ${preset.name}');
        }
        referenceDhuhr ??= times.dhuhr;
        expect(
          times.dhuhr.difference(referenceDhuhr).inMinutes.abs(),
          lessThanOrEqualTo(1),
          reason: preset.name,
        );
      }
    });

    test('the presets really do differ on Fajr', () {
      // Guards against a preset silently collapsing to the same angles.
      final DateTime egyptian = adhan.PrayerTimes(
        adhan.Coordinates(30.0444, 31.2357),
        adhan.DateComponents(2024, 1, 15),
        _params(CalculationPreset.egyptian),
      ).fajr;
      final DateTime northAmerica = adhan.PrayerTimes(
        adhan.Coordinates(30.0444, 31.2357),
        adhan.DateComponents(2024, 1, 15),
        _params(CalculationPreset.northAmerica),
      ).fajr;
      // ISNA uses a 15° Fajr angle vs. the Egyptian 19.5°, so it is later.
      expect(northAmerica.isAfter(egyptian), isTrue);
    });

    test('southern, northern and equatorial latitudes all produce a full day',
        () {
      // Guards the high-latitude rule: these must not yield a null or a
      // reversed prayer time.
      for (final (String, double, double) place
          in <(String, double, double)>[
        ('Sydney', -33.8688, 151.2093),
        ('Reykjavik', 64.1466, -21.9426),
        ('Cairo', 30.0444, 31.2357),
        ('Nairobi', -1.2921, 36.8219),
      ]) {
        final adhan.PrayerTimes times = adhan.PrayerTimes(
          adhan.Coordinates(place.$2, place.$3),
          adhan.DateComponents(2024, 3, 20),
          _params(CalculationPreset.karachi),
        );
        expect(times.fajr.isBefore(times.dhuhr), isTrue, reason: place.$1);
        expect(times.dhuhr.isBefore(times.maghrib), isTrue, reason: place.$1);
      }
    });

    test('the far north: adhan itself gives up inside the polar circle', () {
      // Inside the polar circles the sun can stay below the horizon all day, so
      // `adhan`'s solar maths yields NaN and throws from `TimeComponents`.
      // This is a documented upstream limitation, NOT something the app can
      // compute around — which is exactly why `PrayerTimesNotifier._recompute`
      // wraps the call and shows an Arabic explanation instead of crashing.
      expect(
        () => adhan.PrayerTimes(
          adhan.Coordinates(69.6492, 18.9553), // Tromso, Norway
          adhan.DateComponents(2024, 6, 21),
          _params(CalculationPreset.karachi),
        ),
        throwsA(anything),
      );
    });

    test('just inside the circle the timetable is still well ordered', () {
      // Reykjavik (64°N) is below the Arctic Circle, so it must still work in
      // both solstices — this is the boundary the guard must not trip over.
      for (final CalculationPreset preset in <CalculationPreset>[
        CalculationPreset.karachi,
        CalculationPreset.muslimWorldLeague,
      ]) {
        for (final (int, int) month in <(int, int)>[(6, 21), (12, 21)]) {
          final adhan.PrayerTimes times = adhan.PrayerTimes(
            adhan.Coordinates(64.1466, -21.9426),
            adhan.DateComponents(2024, month.$1, month.$2),
            _params(preset),
          );
          expect(times.sunrise.isBefore(times.maghrib), isTrue,
              reason: '${preset.name} ${month.$1}/${month.$2}');
        }
      }
    });
  });
}
