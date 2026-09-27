import 'dart:math' as math;

/// Helpers for the compass/Qibla maths.
///
/// Every angle in this app is expressed in **degrees**, measured clockwise with
/// 0° pointing north — the same convention used by `flutter_compass_v2`,
/// `flutter_qiblah` and `adhan`.
class Angles {
  Angles._();

  /// Normalises any angle into the `[0, 360)` range.
  ///
  /// `flutter_qiblah` returns the Qibla rotation as `heading + (360 - offset)`,
  /// which can exceed 360° (e.g. 650°). Comparing such a raw value with
  /// `abs() < 3` — as the previous implementation did — never succeeds, so
  /// normalising first is what makes the "aligned" state work at all.
  static double normalize360(double degrees) {
    if (degrees.isNaN || degrees.isInfinite) return 0;
    final double value = degrees % 360;
    return value < 0 ? value + 360 : value;
  }

  /// Normalises any angle into the `(-180, 180]` range.
  ///
  /// Use this for *relative* angles: `-12` means "12° to the left",
  /// `+12` means "12° to the right".
  static double normalize180(double degrees) {
    final double value = normalize360(degrees);
    return value > 180 ? value - 360 : value;
  }

  /// Shortest signed rotation (in degrees) that takes [from] to [to].
  static double difference(double from, double to) => normalize180(to - from);

  /// Great-circle distance between two coordinates, in kilometres.
  ///
  /// Used to show how far the user is from the Kaaba.
  static double distanceInKm({
    required double fromLatitude,
    required double fromLongitude,
    required double toLatitude,
    required double toLongitude,
  }) {
    const double earthRadiusKm = 6371.0088;
    final double dLat = toRadians(toLatitude - fromLatitude);
    final double dLon = toRadians(toLongitude - fromLongitude);
    final double lat1 = toRadians(fromLatitude);
    final double lat2 = toRadians(toLatitude);
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// Converts degrees to radians.
  static double toRadians(double degrees) => degrees * math.pi / 180;

  /// Converts radians to degrees.
  static double toDegrees(double radians) => radians * 180 / math.pi;

  /// The Kaaba (Masjid al-Haram) coordinates used for the bearing/distance.
  static const double kaabaLatitude = 21.4224779;
  static const double kaabaLongitude = 39.8251832;
}

/// A circular low-pass filter for compass headings.
///
/// A plain exponential average breaks at the 359° → 0° wrap-around (the needle
/// would spin the long way round); averaging the sine/cosine components keeps
/// the interpolation on the short arc. This removes most of the magnetometer
/// jitter without adding noticeable lag.
class HeadingSmoother {
  HeadingSmoother({this.smoothing = 0.2});

  /// 0 = frozen, 1 = no smoothing at all.
  final double smoothing;

  double _sinSum = 0;
  double _cosSum = 0;
  bool _primed = false;

  /// Feeds a raw heading (0-360°) and returns the smoothed heading.
  double add(double heading) {
    final double radians = Angles.toRadians(Angles.normalize360(heading));
    final double sin = math.sin(radians);
    final double cos = math.cos(radians);
    if (!_primed) {
      _sinSum = sin;
      _cosSum = cos;
      _primed = true;
    } else {
      _sinSum += smoothing * (sin - _sinSum);
      _cosSum += smoothing * (cos - _cosSum);
    }
    return Angles.normalize360(Angles.toDegrees(math.atan2(_sinSum, _cosSum)));
  }

  /// Forgets the history — call after a permission change or a calibration.
  void reset() {
    _primed = false;
    _sinSum = 0;
    _cosSum = 0;
  }
}
