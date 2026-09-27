// Regression tests for the Qibla compass maths.
//
// These run without a device, a sensor or a permission dialog: they exercise the
// pure functions that `QiblaScreen` uses, plus the plugin's own bearing
// algorithm (copied verbatim from `flutter_qiblah`'s `Utils.getOffsetFromNorth`)
// to prove the two agree for real locations and that the *old* implementation
// could never report "aligned".
//
//   flutter test test/qibla_math_test.dart

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:salat_al_saadia/core/utils/angles.dart';
import 'package:salat_al_saadia/features/qibla/presentation/screens/qibla_screen.dart';

/// `latitude`, `longitude`, published Qibla bearing (degrees from true north).
const List<(String, double, double, double)> _cities =
    <(String, double, double, double)>[
  ('Cairo', 30.0444, 31.2357, 136.14),
  ('Riyadh', 24.7136, 46.6753, 243.80),
  ('London', 51.5074, -0.1278, 118.99),
  ('New York', 40.7128, -74.0060, 58.48),
  ('Sydney', -33.8688, 151.2093, 277.50),
  ('Jakarta', -6.2088, 106.8456, 295.15),
  ('Tokyo', 35.6762, 139.6503, 293.02),
  ('Los Angeles', 34.0522, -118.2437, 23.86),
  ('Nairobi', -1.2921, 36.8219, 7.20),
  ('Istanbul', 41.0082, 28.9784, 151.68),
  ('Moscow', 55.7558, 37.6173, 176.36),
  ('Cape Town', -33.9249, 18.4241, 23.36),
];

/// Verbatim port of `flutter_qiblah` 3.2.0 `Utils.getOffsetFromNorth`, i.e. what
/// `QiblahDirection.offset` contains. Kept here so the test can prove that our
/// `atan2` implementation matches the plugin everywhere it is correct, and that
/// the plugin's value is *not* normalised (it returns negatives).
double _pluginOffsetFromNorth(double currentLatitude, double currentLongitude) {
  const double deLa = 21.422487; // Kaaba latitude, radians below
  const double deLo = 39.826206; // Kaaba longitude, radians below
  final double laRad = Angles.toRadians(currentLatitude);
  final double loRad = Angles.toRadians(currentLongitude);
  final double deLaRad = Angles.toRadians(deLa);
  final double deLoRad = Angles.toRadians(deLo);

  double toDegrees = Angles.toDegrees(
    math.atan(
      math.sin(deLoRad - loRad) /
          ((math.cos(laRad) * math.tan(deLaRad)) -
              (math.sin(laRad) * math.cos(deLoRad - loRad))),
    ),
  );

  if (laRad > deLaRad) {
    if ((loRad > deLoRad || loRad < Angles.toRadians(-180.0) + deLoRad) &&
        toDegrees > 0.0 &&
        toDegrees <= 90.0) {
      toDegrees += 180.0;
    } else if (loRad <= deLoRad &&
        loRad >= Angles.toRadians(-180.0) + deLoRad &&
        toDegrees > -90.0 &&
        toDegrees < 0.0) {
      toDegrees += 180.0;
    }
  }
  if (laRad < deLaRad) {
    if ((loRad > deLoRad || loRad < Angles.toRadians(-180.0) + deLoRad) &&
        toDegrees > 0.0 &&
        toDegrees < 90.0) {
      toDegrees += 180.0;
    }
    if (loRad <= deLoRad &&
        loRad >= Angles.toRadians(-180.0) + deLoRad &&
        toDegrees > -90.0 &&
        toDegrees <= 0.0) {
      toDegrees += 180.0;
    }
  }
  return toDegrees;
}

/// What `QiblaScreen._onQiblahReading` computes (same expressions).
double _alignmentError({
  required double bearing,
  required double magneticHeading,
  required double declination,
}) {
  final double trueHeading = Angles.normalize360(magneticHeading + declination);
  return Angles.difference(trueHeading, bearing);
}

void main() {
  group('trueBearingToKaaba', () {
    for (final (String name, double lat, double lon, double expected)
        in _cities) {
      test('$name matches the published bearing', () {
        final double bearing = trueBearingToKaaba(lat, lon);
        expect(bearing, greaterThanOrEqualTo(0.0));
        expect(bearing, lessThan(360.0));
        expect(
          Angles.normalize180(bearing - expected).abs(),
          lessThan(0.5),
          reason: '$name: got ${bearing.toStringAsFixed(2)}°, expected '
              '${expected.toStringAsFixed(2)}°',
        );
      });
    }

    test('is always normalised, even in the southern/western hemisphere', () {
      // These are exactly the cases where the plugin's `atan()` heuristics
      // return negative values (Sydney -82.5°, Jakarta -64.9°, Honolulu -23.1°).
      expect(trueBearingToKaaba(-33.8688, 151.2093), greaterThan(0.0));
      expect(trueBearingToKaaba(-6.2088, 106.8456), greaterThan(0.0));
      expect(trueBearingToKaaba(21.3069, -157.8583), greaterThan(0.0));
    });

    test('agrees with flutter_qiblah\'s own formula for real locations', () {
      for (final (String name, double lat, double lon, _) in _cities) {
        final double mine = trueBearingToKaaba(lat, lon);
        final double plugin =
            Angles.normalize360(_pluginOffsetFromNorth(lat, lon));
        expect(
          Angles.normalize180(mine - plugin).abs(),
          lessThan(0.05),
          reason: '$name: ours=${mine.toStringAsFixed(3)}° '
              'plugin=${plugin.toStringAsFixed(3)}°',
        );
      }
    });

    test('the plugin offset is NOT normalised (the original bug)', () {
      // The old screen tested `qibla.qiblah.abs() < 3`, but that value is built
      // from an unnormalised offset and can exceed 360°, so the "aligned" state
      // could never become true.
      final double signedOffset = _pluginOffsetFromNorth(-33.8688, 151.2093);
      expect(signedOffset, lessThan(0.0)); // Sydney: -82.5°

      // QiblahDirection semantics: qiblah = heading + (360 - offset).
      const double heading = 277.5; // facing the Qibla
      final double rawQiblah = heading + (360 - signedOffset);
      expect(rawQiblah, greaterThan(360.0));
      expect(rawQiblah.abs(), greaterThan(3.0));

      // Normalising first — what Angles.normalize180 now does — fixes it.
      expect(Angles.normalize180(rawQiblah).abs(), lessThan(0.001));
    });
  });

  group('alignment window (±3°)', () {
    final double cairoBearing = trueBearingToKaaba(30.0444, 31.2357);
    const double declination = 4.2; // ≈ Egypt

    test('error is 0 when the true heading equals the bearing', () {
      final double error = _alignmentError(
        bearing: cairoBearing,
        magneticHeading: cairoBearing - declination,
        declination: declination,
      );
      expect(error.abs(), lessThan(1e-9));
      expect(error.abs() <= 3.0, isTrue);
    });

    test('inside the window is aligned, outside is not', () {
      double errorAt(double offset) => _alignmentError(
            bearing: cairoBearing,
            magneticHeading: cairoBearing + offset - declination,
            declination: declination,
          );

      expect(errorAt(0).abs() <= 3.0, isTrue);
      expect(errorAt(2.9).abs() <= 3.0, isTrue);
      expect(errorAt(-2.9).abs() <= 3.0, isTrue);
      expect(errorAt(3.1).abs() <= 3.0, isFalse);
      expect(errorAt(-3.1).abs() <= 3.0, isFalse);
    });

    test('sign tells the user which way to turn', () {
      // Negative error → the Qibla is anticlockwise from the phone's heading.
      final double one = _alignmentError(
        bearing: cairoBearing,
        magneticHeading: cairoBearing + 20 - declination,
        declination: declination,
      );
      final double other = _alignmentError(
        bearing: cairoBearing,
        magneticHeading: cairoBearing - 20 - declination,
        declination: declination,
      );
      expect(one, lessThan(0));
      expect(other, greaterThan(0));
    });
  });

  group('Angles normalisation (the 359° → 0° wrap)', () {
    test('difference() takes the short arc', () {
      expect(Angles.difference(359.0, 1.0), closeTo(2.0, 1e-9));
      expect(Angles.difference(1.0, 359.0), closeTo(-2.0, 1e-9));
      expect(Angles.difference(0.0, 180.0), closeTo(180.0, 1e-9));
      expect(Angles.difference(0.0, 181.0), closeTo(-179.0, 1e-9));
      // Exactly 180° is the convention boundary: normalize180 keeps +180.
      expect(Angles.difference(10.0, 190.0), closeTo(180.0, 1e-9));
    });

    test('normalize360 handles negatives, overflow and NaN', () {
      expect(Angles.normalize360(-10), closeTo(350, 1e-9));
      expect(Angles.normalize360(370), closeTo(10, 1e-9));
      expect(Angles.normalize360(720), closeTo(0, 1e-9));
      expect(Angles.normalize360(double.nan), 0);
    });
  });

  group('magneticDeclination (World Magnetic Model)', () {
    test('returns a usable, correctly signed value', () {
      // Guards the silent `catch (_) => 0` fallback inside `magneticDeclination`:
      // a broken model must fail here instead of quietly skipping the correction.
      expect(magneticDeclination(30.0444, 31.2357), isNot(0));

      final double cairo = magneticDeclination(30.0444, 31.2357);
      final double newYork = magneticDeclination(40.7128, -74.0060);
      final double sydney = magneticDeclination(-33.8688, 151.2093);

      // Egypt: a few degrees east. US east coast: west (negative).
      // Australia: clearly east. Bounds are deliberately loose so the test keeps
      // passing as the WMM epoch advances.
      expect(cairo, inInclusiveRange(1.0, 8.0));
      expect(newYork, inInclusiveRange(-18.0, -8.0));
      expect(sydney, inInclusiveRange(8.0, 16.0));
    });

    test('never throws for extreme coordinates', () {
      expect(() => magneticDeclination(89.9, 179.9), returnsNormally);
      expect(() => magneticDeclination(-89.9, -179.9), returnsNormally);
      expect(() => magneticDeclination(0.0, 0.0), returnsNormally);
    });
  });

  group('distance to the Kaaba', () {
    test('Cairo is roughly 1,300 km away', () {
      final double km = Angles.distanceInKm(
        fromLatitude: 30.0444,
        fromLongitude: 31.2357,
        toLatitude: Angles.kaabaLatitude,
        toLongitude: Angles.kaabaLongitude,
      );
      expect(km, inInclusiveRange(1200, 1500));
    });
  });
}
