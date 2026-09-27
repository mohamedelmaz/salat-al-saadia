import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// Outcome of asking for the Android/iOS location permission.
enum LocationAccessStatus {
  granted,

  /// GPS/location services are switched off device-wide.
  serviceDisabled,

  /// The user dismissed the system dialog with "deny".
  permissionDenied,

  /// The user chose "don't ask again" / the permission is blocked in settings.
  permissionDeniedForever,

  /// The permission was granted but no fix arrived before the timeout.
  timedOut,
  error,
}

/// Result of [LocationAccess.ensureAccess].
class LocationAccessResult {
  const LocationAccessResult(this.status, {this.position, this.detail});

  final LocationAccessStatus status;

  /// Last known / freshly acquired position, when available.
  final Position? position;

  /// Technical detail (exception text) for debugging.
  final String? detail;

  bool get isGranted => status == LocationAccessStatus.granted;

  /// Arabic, user-facing explanation + what to do about it.
  String get message {
    switch (status) {
      case LocationAccessStatus.granted:
        return 'تم منح إذن الموقع بنجاح.';
      case LocationAccessStatus.serviceDisabled:
        return 'خدمة تحديد الموقع (GPS) مغلقة في الجهاز. يرجى تشغيلها للحصول على اتجاه القبلة الصحيح.';
      case LocationAccessStatus.permissionDenied:
        return 'لم يتم منح إذن الموقع. بدون هذا الإذن لا يمكن حساب اتجاه القبلة بدقة.';
      case LocationAccessStatus.permissionDeniedForever:
        return 'تم رفض إذن الموقع نهائياً. يرجى تمكينه من إعدادات التطبيق.';
      case LocationAccessStatus.timedOut:
        return 'لم يتم تحديد موقعك بعد. تأكد من وضوح السماء أو أعد المحاولة.';
      case LocationAccessStatus.error:
        return 'تعذر تحديد الموقع. يرجى المحاولة مرة أخرى.';
    }
  }
}

/// Thin, dependency-free wrapper around `geolocator` that implements the exact
/// runtime-permission flow Android needs for `ACCESS_FINE_LOCATION`.
///
/// Both the manifest entries (`ACCESS_FINE_LOCATION` + `ACCESS_COARSE_LOCATION`)
/// and this runtime request are required since Android 6 — that is why the Qibla
/// screen could never receive a position (and therefore never received a Qibla
/// bearing) in the previous implementation, which never asked for the
/// permission at all.
class LocationAccess {
  LocationAccess._();

  /// High accuracy + a hard timeout so the UI is never stuck waiting.
  static const LocationSettings highAccuracySettings = LocationSettings(
    accuracy: LocationAccuracy.high,
    timeLimit: Duration(seconds: 20),
  );

  /// Shows the system permission dialog when needed and reports the outcome.
  ///
  /// Note: `Geolocator.requestPermission()` *is* the `ACCESS_FINE_LOCATION`
  /// request — geolocator asks for `fine` first and automatically downgrades to
  /// `coarse` only when the user picks "approximate" on Android 12+.
  static Future<LocationAccessStatus> requestPermission() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      switch (permission) {
        case LocationPermission.deniedForever:
          return LocationAccessStatus.permissionDeniedForever;
        case LocationPermission.whileInUse:
        case LocationPermission.always:
          return LocationAccessStatus.granted;
        case LocationPermission.denied:
        case LocationPermission.unableToDetermine:
          return LocationAccessStatus.permissionDenied;
      }
    } catch (_) {
      return LocationAccessStatus.error;
    }
  }

  /// Permission + service check, optionally followed by a single position fix.
  static Future<LocationAccessResult> ensureAccess(
      {bool requestPosition = true}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationAccessResult(LocationAccessStatus.serviceDisabled);
      }

      final LocationAccessStatus permission = await requestPermission();
      if (permission != LocationAccessStatus.granted) {
        return LocationAccessResult(permission);
      }

      if (!requestPosition) {
        return const LocationAccessResult(LocationAccessStatus.granted);
      }

      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: highAccuracySettings,
      );
      return LocationAccessResult(LocationAccessStatus.granted,
          position: position);
    } on TimeoutException catch (error) {
      return LocationAccessResult(LocationAccessStatus.timedOut,
          detail: error.toString());
    } catch (error) {
      return LocationAccessResult(LocationAccessStatus.error,
          detail: error.toString());
    }
  }

  /// Opens the app's permission screen (used for "denied forever").
  static Future<bool> openAppSettings() => Geolocator.openAppSettings();

  /// Opens the system location settings (used when GPS is switched off).
  static Future<bool> openLocationSettings() =>
      Geolocator.openLocationSettings();
}
