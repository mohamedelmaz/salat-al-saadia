import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_compass_v2/flutter_compass_v2.dart';
import 'package:flutter_qiblah/flutter_qiblah.dart';
import 'package:geomag/geomag.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vibration/vibration.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/location/location_access.dart';
import '../../../../core/utils/angles.dart';

// =============================================================================
//  Qibla compass — how the maths works (short version)
// =============================================================================
//
//  1. Hardware / permissions
//     `flutter_qiblah` merges the rotation-vector heading (`flutter_compass_v2`)
//     with a GPS fix (`geolocator`). Both the manifest entries *and* a runtime
//     `ACCESS_FINE_LOCATION` request are needed on Android 6+ (see
//     `core/location/location_access.dart`), otherwise the stream stays silent
//     and no Qibla direction is ever produced.
//
//  2. Bearing to the Kaaba (true north)
//         θ = atan2( sin Δλ · cos φ₂ ,  cos φ₁ · sin φ₂ − sin φ₁ · cos φ₂ · cos Δλ )
//     → `trueBearingToKaaba`. `atan2` resolves the quadrant by construction,
//     which is why it is used instead of the plugin's `atan()` + heuristics.
//
//  3. Magnetic vs. true north
//     Android/`flutter_compass_v2` report the **magnetic** azimuth, while the
//     Qibla bearing is relative to **true** north. The World Magnetic Model
//     (`geomag`) supplies the local declination `δ`, so
//         headingTrue = normalize360(headingMagnetic + δ)
//     Without this step the needle is systematically off by δ (≈ +4° in Egypt,
//     up to ±13° in North America / northern Canada).
//
//  4. Relative angle (what the user actually sees)
//         error = normalize180(bearingTrue − headingTrue)
//     `error == 0` → facing the Kaaba; `error > 0` → the Kaaba is clockwise
//     from where the phone points (turn right); `error < 0` → turn left.
//
//  5. Rendering
//     * the dial is rotated by `−headingTrue`, so its north mark always sits on
//       real north, whichever way the phone is turned;
//     * the Kaaba needle is rotated by `error`, so it always points at the real
//       Qibla — independently of the dial's own rotation.
//     `flutter_qiblah` encodes the same relative angle in `qiblah.qiblah`
//     (`normalize360(−error)` *before* the declination step), which is why the
//     plugin's own example rotates its needle by `−qiblah`.
// =============================================================================

/// Angular window (degrees) inside which the device counts as "facing Qibla".
/// A magnetometer is only accurate to a couple of degrees, so a tighter window
/// would make the success state flicker.
const double _alignmentToleranceDegrees = 3;

/// A sensor event only repaints the dial once the heading moved by this much.
/// The compass fires ~30×/second; throttling keeps low-end devices smooth while
/// the needle still reacts instantly to a real turn.
const double _repaintThresholdDegrees = 0.5;

/// Every state this screen can be in; each one gets its own explanatory UI.
enum _QiblaStage {
  /// Asking the platform about sensors, permissions and the GPS fix.
  checking,

  /// Compass + Qibla are live (readings may still be arriving).
  ready,

  /// No rotation-vector / magnetometer sensor on this device.
  unsupported,

  /// `ACCESS_FINE_LOCATION` refused once — the system dialog can be shown again.
  permissionDenied,

  /// `ACCESS_FINE_LOCATION` blocked permanently ("don't ask again").
  permissionDeniedForever,

  /// Location (GPS) is switched off device-wide.
  locationDisabled,

  /// Unexpected platform error.
  failed,
}

// -----------------------------------------------------------------------------
//  Qibla geometry helpers
// -----------------------------------------------------------------------------

/// Initial great-circle **bearing** (0-360°, clockwise from *true* north) from
/// `latitude`/`longitude` to the Kaaba.
///
///     θ = atan2( sin Δλ · cos φ₂ ,  cos φ₁ · sin φ₂ − sin φ₁ · cos φ₂ · cos Δλ )
///
/// `φ₁/λ₁` are the observer's coordinates, `φ₂/λ₂` the Kaaba's and `Δλ = λ₂ − λ₁`.
/// `atan2` picks the correct quadrant on its own, so the result is valid
/// everywhere on the globe — including southern latitudes and western
/// longitudes, where the plugin's `atan()` + quadrant heuristics can return an
/// unnormalised (negative) bearing.
///
/// Public (and pure) on purpose: `test/qibla_math_test.dart` checks it against
/// reference bearings for cities all over the world.
double trueBearingToKaaba(double latitude, double longitude) {
  final double phi1 = Angles.toRadians(latitude); // observer latitude
  final double phi2 = Angles.toRadians(Angles.kaabaLatitude); // Kaaba latitude
  final double deltaLambda =
      Angles.toRadians(Angles.kaabaLongitude - longitude); // longitude delta

  final double y = math.sin(deltaLambda) * math.cos(phi2);
  final double x = math.cos(phi1) * math.sin(phi2) -
      math.sin(phi1) * math.cos(phi2) * math.cos(deltaLambda);

  return Angles.normalize360(Angles.toDegrees(math.atan2(y, x)));
}

/// Magnetic declination `δ` for a position, from the bundled World Magnetic
/// Model: the angle between magnetic north and true north (positive = magnetic
/// north lies *east* of true north).
///
/// Public (and pure) on purpose — see `test/qibla_math_test.dart`.
double magneticDeclination(double latitude, double longitude) {
  try {
    return GeoMag().calculate(latitude, longitude).dec;
  } catch (_) {
    // A model failure must never take the compass down: 0 falls back to the
    // uncorrected magnetic frame, which is what the raw plugin reports anyway.
    return 0;
  }
}

/// Arabic label for the accuracy Android reports for the magnetometer
/// (the values are deviations in degrees: 15 high, 30 medium, 45 low).
String _accuracyLabel(double? accuracy) {
  if (accuracy == null) return 'دقة غير معروفة';
  if (accuracy <= 15) return 'دقة عالية';
  if (accuracy <= 30) return 'دقة متوسطة';
  return 'دقة منخفضة';
}

/// Painter helper: draws `text` centred on `center`.
void _paintCenteredText(
  Canvas canvas,
  String text,
  TextStyle style,
  Offset center,
) {
  final TextPainter painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.rtl,
    textAlign: TextAlign.center,
  )..layout();
  painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
}

// -----------------------------------------------------------------------------
//  Screen
// -----------------------------------------------------------------------------

/// Qibla compass built on `flutter_qiblah` (compass + GPS) with:
/// * a runtime `ACCESS_FINE_LOCATION` flow,
/// * magnetic-declination correction (true north),
/// * an `atan2`-based Kaaba bearing,
/// * an animated figure-8 calibration hint and
/// * a gold "you are facing the Qibla" success state.
class QiblaScreen extends StatefulWidget {
  const QiblaScreen({super.key});

  @override
  State<QiblaScreen> createState() => _QiblaScreenState();
}

class _QiblaScreenState extends State<QiblaScreen> with WidgetsBindingObserver {
  // --- platform / lifecycle --------------------------------------------------
  _QiblaStage _stage = _QiblaStage.checking;
  String? _stageDetail;

  /// Guards against overlapping platform round-trips (double taps, a resume
  /// event arriving while a permission dialog is still open…).
  bool _busy = false;

  /// True while this tab is the one actually on screen. `MainNavigationScreen`
  /// wraps every tab in a `TickerMode`, which is Flutter's idiomatic "am I
  /// visible?" signal (see [didChangeDependencies]).
  ///
  /// This is required because `IndexedStack` builds *all* five tabs at
  /// start-up: without the guard the location permission dialog would pop up
  /// while the user is still looking at the prayer-times tab.
  bool _isVisible = false;

  /// Set while the user is expected to fix something outside the app (a
  /// permission in Settings, the GPS toggle), so the resume handler knows a
  /// re-check is worth it.
  bool _awaitingSettingsReturn = false;

  // --- live sensor data ------------------------------------------------------
  StreamSubscription<QiblahDirection>? _qiblaSubscription;
  StreamSubscription<CompassEvent>? _accuracySubscription;

  /// Circular low-pass filter that removes magnetometer jitter without adding
  /// visible lag (see `core/utils/angles.dart`).
  final HeadingSmoother _headingSmoother = HeadingSmoother();

  /// Magnetometer accuracy reported by Android (15 / 30 / 45 / `null`). Drives
  /// the calibration hint. `flutter_qiblah` does not forward it, so it is read
  /// from the shared `flutter_compass_v2` broadcast stream.
  double? _sensorAccuracy;

  Object? _streamError;
  bool _hasReading = false;

  // --- geometry (degrees, 0° = north, growing clockwise) ---------------------
  double? _latitude;
  double? _longitude;

  /// Absolute (true-north) bearing to the Kaaba — it only depends on the
  /// position, not on how the phone is held.
  double? _qiblaBearing;

  /// Local magnetic declination applied to the sensor's magnetic heading.
  double _declination = 0;
  double? _distanceToKaabaKm;

  /// Smoothed magnetic heading straight from the sensor.
  double _headingMagnetic = 0;

  /// Magnetic heading corrected to true north — this is what the dial follows.
  double _headingTrue = 0;

  /// Bearing used for display/pointer (our own when available, else the
  /// plugin's offset).
  double _bearing = 0;

  /// Signed angle from the device's heading to the Qibla (clockwise positive).
  double _alignmentError = 0;

  // --- calibration hint ------------------------------------------------------
  bool _showCalibrationHint = true;
  double? _accuracyWhenHintDismissed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The bootstrap itself is started from `didChangeDependencies`, which knows
    // whether this tab is actually visible (see `_isVisible`).
  }

  /// Starts/stops the sensor work when the user switches bottom-navigation tabs.
  ///
  /// `TickerMode` flips to `false` for the tabs that `IndexedStack` keeps alive
  /// but does not paint, so it doubles as a cheap, dependency-free visibility
  /// signal (and it also mutes the calibration animation off screen).
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final bool visible = TickerMode.valuesOf(context).enabled;
    if (visible == _isVisible) return;
    _isVisible = visible;

    if (!visible) {
      // Off screen: release the magnetometer. The last reading is kept in
      // state, so the dial is immediately correct again on return.
      _stopStream();
      return;
    }

    if (_stage == _QiblaStage.ready) {
      // Back on a working compass: resuming the stream is instant (permission
      // and position are already resolved), so the user does not see a spinner.
      _startStream();
    } else {
      // First visit, or a state the user has to fix first (permission, GPS).
      _bootstrap();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _qiblaSubscription?.cancel();
    _accuracySubscription?.cancel();
    // Drops the plugin's cached broadcast stream so the next visit rebuilds it
    // instead of reusing a possibly stale/errored one.
    FlutterQiblah().dispose();
    super.dispose();
  }

  /// Re-checks the platform when the user may have changed something outside
  /// the app — typically right after granting the permission in Settings.
  ///
  /// A plain "denied" state is deliberately *not* re-requested here: on Android
  /// every resume would pop the system dialog again. That case has an explicit
  /// button in the UI instead.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;

    final bool cameBackFromSettings = _awaitingSettingsReturn;
    _awaitingSettingsReturn = false;

    if (cameBackFromSettings ||
        _stage == _QiblaStage.permissionDeniedForever ||
        _stage == _QiblaStage.locationDisabled) {
      _bootstrap();
    }
  }

  // ---------------------------------------------------------------------------
  //  Platform bootstrap: sensors → permission → GPS fix
  // ---------------------------------------------------------------------------

  Future<void> _bootstrap() async {
    if (_busy) return;
    _busy = true;

    await _stopStream();
    if (!mounted) {
      _busy = false;
      return;
    }
    setState(() {
      _stage = _QiblaStage.checking;
      _stageDetail = null;
      _streamError = null;
      _hasReading = false;
    });

    // The position-derived values are reset up-front on purpose: a retry (or a
    // resume) whose GPS fix times out must NOT keep showing the bearing and the
    // declination of the *previous* fix — `_qiblaBearing` is preferred over the
    // plugin's own offset in `_onQiblahReading`, so a stale value would silently
    // point the needle at the Kaaba as seen from the old location.
    _latitude = null;
    _longitude = null;
    _qiblaBearing = null;
    _distanceToKaabaKm = null;
    _declination = 0;

    try {
      // 1. Hardware: the rotation-vector sensor is mandatory. Without it the
      //    plugin never emits a heading, so tell the user instead of showing an
      //    endless spinner.
      final bool sensorSupported =
          await FlutterQiblah.androidDeviceSensorSupport() ?? false;
      if (!mounted) return;
      if (!sensorSupported) {
        setState(() => _stage = _QiblaStage.unsupported);
        return;
      }

      // 2. Runtime permission (`ACCESS_FINE_LOCATION`) + GPS fix. LocationAccess
      //    performs exactly the runtime request Android 6+ requires — the
      //    manifest entries alone are not enough — and reports *why* it failed
      //    (denied, denied forever, GPS off, timeout) so the UI can react.
      final LocationAccessResult access = await LocationAccess.ensureAccess();
      if (!mounted) return;

      switch (access.status) {
        case LocationAccessStatus.permissionDenied:
          setState(() => _stage = _QiblaStage.permissionDenied);
          return;
        case LocationAccessStatus.permissionDeniedForever:
          setState(() => _stage = _QiblaStage.permissionDeniedForever);
          return;
        case LocationAccessStatus.serviceDisabled:
          setState(() => _stage = _QiblaStage.locationDisabled);
          return;
        case LocationAccessStatus.timedOut:
        case LocationAccessStatus.error:
          // Permission is fine but the fix is slow: the heading signal is still
          // useful and the plugin keeps looking for a position, so carry on with
          // a visible warning instead of blocking the whole screen.
          _stageDetail = access.message;
          break;
        case LocationAccessStatus.granted:
          _stageDetail = null;
          break;
      }

      // 3. Position-derived maths (only possible once a fix exists).
      final position = access.position;
      if (position != null) {
        final double latitude = position.latitude;
        final double longitude = position.longitude;
        _latitude = latitude;
        _longitude = longitude;

        // Absolute bearing from true north → "القبلة على زاوية 245°".
        _qiblaBearing = trueBearingToKaaba(latitude, longitude);

        // Magnetic → true north correction for the sensor heading.
        _declination = magneticDeclination(latitude, longitude);

        _distanceToKaabaKm = Angles.distanceInKm(
          fromLatitude: latitude,
          fromLongitude: longitude,
          toLatitude: Angles.kaabaLatitude,
          toLongitude: Angles.kaabaLongitude,
        );
      }

      _headingSmoother.reset();

      if (!mounted) return;
      setState(() => _stage = _QiblaStage.ready);
      // The user may have switched tabs while the permission dialog / GPS fix
      // was running, in which case nothing should be subscribed yet.
      if (_isVisible) _startStream();
    } catch (error) {
      if (mounted) {
        setState(() {
          _stage = _QiblaStage.failed;
          _stageDetail = error.toString();
        });
      }
    } finally {
      _busy = false;
    }
  }

  /// Retry button / AppBar action: forget the cached stream (which may be the
  /// very thing that failed) and run the whole boot sequence again.
  Future<void> _retry() async {
    _headingSmoother.reset();
    FlutterQiblah().dispose();
    if (mounted) {
      setState(() {
        _streamError = null;
        _hasReading = false;
      });
    }
    await _bootstrap();
  }

  void _startStream() {
    // `flutter_qiblah` does not expose the magnetometer accuracy, so a second
    // (free) subscription on the shared `flutter_compass_v2` broadcast stream
    // feeds the calibration hint.
    _accuracySubscription = FlutterCompass.events?.listen(
      (CompassEvent event) => _onAccuracy(event.accuracy),
      onError: (Object _) {},
    );

    _qiblaSubscription = FlutterQiblah.qiblahStream.listen(
      _onQiblahReading,
      onError: (Object error) {
        if (!mounted) return;
        setState(() => _streamError = error);
      },
    );
  }

  Future<void> _stopStream() async {
    await _qiblaSubscription?.cancel();
    await _accuracySubscription?.cancel();
    _qiblaSubscription = null;
    _accuracySubscription = null;
  }

  // ---------------------------------------------------------------------------
  //  Sensor callbacks
  // ---------------------------------------------------------------------------

  /// Called ~30×/second by the plugin while the compass is live.
  void _onQiblahReading(QiblahDirection data) {
    if (!mounted) return;

    // --- 1. Heading, smoothed and moved from the magnetic to the true frame --
    final double magneticHeading = _headingSmoother.add(data.direction);
    final double trueHeading =
        Angles.normalize360(magneticHeading + _declination);

    // --- 2. Bearing to the Kaaba --------------------------------------------
    // Our own value (computed from the acquired fix with the app's Kaaba
    // constants) is preferred; `data.offset` is the plugin's equivalent and is
    // only used as a fallback when the GPS fix timed out.
    final double bearing = _qiblaBearing ?? Angles.normalize360(data.offset);

    // --- 3. Signed angle from "where the phone points" to "where the Kaaba is"
    //        (clockwise positive → turn right, negative → turn left).
    //
    //        `flutter_qiblah` exposes the very same quantity as `data.qiblah`
    //        (`data.qiblah == normalize360(-error)`), but measured in the
    //        *magnetic* frame — i.e. without the declination step above and
    //        unnormalised (it can read 400°+), which is exactly what used to
    //        break the `abs() < 3` alignment test.
    final double error = Angles.difference(trueHeading, bearing);
    final bool aligned = error.abs() <= _alignmentToleranceDegrees;

    final bool wasAligned =
        _hasReading && _alignmentError.abs() <= _alignmentToleranceDegrees;
    if (aligned && !wasAligned) _vibrateOnAlignment();

    // Throttle: skip repaints that would not change a single visible pixel.
    final bool moved = !_hasReading ||
        Angles.difference(_headingTrue, trueHeading).abs() >=
            _repaintThresholdDegrees;
    if (!moved && aligned == wasAligned) return;

    setState(() {
      _hasReading = true;
      _headingMagnetic = magneticHeading;
      _headingTrue = trueHeading;
      _bearing = bearing;
      _alignmentError = error;
      _streamError = null;
    });
  }

  /// Magnetometer accuracy (15 high / 30 medium / 45 low / `null` unknown).
  void _onAccuracy(double? accuracy) {
    if (!mounted || accuracy == _sensorAccuracy) return;
    setState(() {
      _sensorAccuracy = accuracy;
      // If the user dismissed the hint earlier, only re-arm it when the
      // calibration gets *worse* than it was at dismissal time.
      final double? atDismissal = _accuracyWhenHintDismissed;
      if (!_showCalibrationHint &&
          accuracy != null &&
          accuracy >= 45 &&
          (atDismissal ?? 0) < 45) {
        _showCalibrationHint = true;
      }
    });
  }

  /// Short haptic pulse the first time the needle reaches the Qibla.
  Future<void> _vibrateOnAlignment() async {
    try {
      if (await Vibration.hasVibrator()) {
        Vibration.vibrate(duration: 80);
      }
    } catch (_) {
      // Haptics are a nice-to-have — never let them break the compass.
    }
  }

  // ---------------------------------------------------------------------------
  //  Derived UI state
  // ---------------------------------------------------------------------------

  /// True when the device points at the Kaaba (±3°).
  bool get _isFacingQibla =>
      _hasReading && _alignmentError.abs() <= _alignmentToleranceDegrees;

  /// Android reports accuracy as a deviation, so ≥ 30° means the magnetometer
  /// needs calibrating (and `null` means it never reported a status at all).
  bool get _needsCalibration {
    final double? accuracy = _sensorAccuracy;
    return accuracy == null || accuracy >= 30;
  }

  bool get _shouldShowCalibrationHint =>
      _showCalibrationHint && _needsCalibration;

  /// User-facing instruction line under the dial.
  String get _turnInstruction {
    if (!_hasReading) return 'جارٍ قراءة المستشعرات…';
    if (_isFacingQibla) return 'أنت تواجه القبلة الآن 🕋';
    final double error = _alignmentError;
    // `error > 0` means the Kaaba sits clockwise from the phone's heading, i.e.
    // rotating the phone clockwise (to the right) closes the gap.
    return 'أدِر الهاتف ${error.abs().toStringAsFixed(0)}° إلى ${error > 0 ? 'اليمين' : 'اليسار'}';
  }

  // ---------------------------------------------------------------------------
  //  Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('اتجاه القبلة'),
        actions: <Widget>[
          IconButton(
            tooltip: 'إعادة المحاولة',
            onPressed: _retry,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: switch (_stage) {
          _QiblaStage.checking => _buildLoading(),
          _QiblaStage.ready => _buildCompassArea(isDark),
          _QiblaStage.unsupported => _buildUnsupported(),
          _QiblaStage.permissionDenied =>
            _buildPermissionDenied(forever: false),
          _QiblaStage.permissionDeniedForever =>
            _buildPermissionDenied(forever: true),
          _QiblaStage.locationDisabled => _buildLocationDisabled(),
          _QiblaStage.failed => _buildFailure(),
        },
      ),
    );
  }

  Widget _buildLoading() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
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
            'جارٍ التحقق من مستشعرات الجهاز وإذن الموقع…',
            style: GoogleFonts.cairo(
              fontSize: 14,
              color: isDark ? Colors.white70 : AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  /// Shared skeleton for every blocking state (no sensor, no permission,
  /// stream failure…): icon badge, title, explanation, optional technical
  /// detail and up to two actions.
  Widget _buildStatusCard({
    required IconData icon,
    required String title,
    required String message,
    List<Widget> actions = const <Widget>[],
    String? detail,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: <Color>[
                    AppColors.primaryEmerald,
                    AppColors.primaryEmeraldLight,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppColors.primaryEmerald.withValues(alpha: 0.28),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Icon(icon, size: 44, color: AppColors.secondaryGold),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : AppColors.primaryEmeraldDark,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: 14,
                height: 1.7,
                color: isDark ? Colors.white70 : AppColors.textMuted,
              ),
            ),
            if (detail != null) ...<Widget>[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white10
                      : Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  detail,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                    fontSize: 11.5,
                    height: 1.6,
                    color: isDark ? Colors.white54 : AppColors.textMuted,
                  ),
                ),
              ),
            ],
            if (actions.isNotEmpty) ...<Widget>[
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: actions,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _primaryButton(String label, IconData icon, VoidCallback onPressed) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primaryEmerald,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Widget _secondaryButton(String label, IconData icon, VoidCallback onPressed) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.secondaryGold,
        side: const BorderSide(color: AppColors.secondaryGold),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  //  Blocking states
  // ---------------------------------------------------------------------------

  Widget _buildUnsupported() {
    return _buildStatusCard(
      icon: Icons.info_outline,
      title: 'جهازك لا يحتوي على بوصلة',
      message:
          'لم نجد مستشعر الاتجاه (Rotation Vector) في هذا الجهاز، وهو المستشعر '
          'اللازم لتحديد اتجاه القبلة. يمكنك تحديد الاتجاه يدوياً من خلال تطبيق '
          'خرائط، أو تجربة جهاز آخر.',
      actions: <Widget>[
        _primaryButton('إعادة المحاولة', Icons.refresh, _retry),
      ],
    );
  }

  Widget _buildPermissionDenied({required bool forever}) {
    return _buildStatusCard(
      icon: Icons.location_off,
      title: 'نحتاج إذن الموقع لحساب القبلة',
      message: forever
          ? 'تم رفض إذن الموقع نهائياً. زاوية القبلة تُحسب من إحداثيات موقعك، '
              'ولا يُرسل موقعك إلى أي جهة خارج جهازك.'
          : 'زاوية القبلة تختلف من مكان لآخر (مثلاً 136° في القاهرة و58° في '
              'نيويورك)، لذلك نحتاج قراءة موقعك — مرة واحدة فقط وحسابها داخل '
              'جهازك — لعرض الاتجاه الصحيح.',
      detail: forever
          ? 'يمكنك تمكين الإذن من: الإعدادات ← التطبيقات ← صلاة-السعدية '
              '← الأذونات ← الموقع.'
          : null,
      actions: <Widget>[
        if (forever)
          _primaryButton(
              'فتح إعدادات التطبيق', Icons.settings, _openAppSettings)
        else
          _primaryButton(
              'السماح بالوصول إلى الموقع', Icons.my_location, _bootstrap),
        if (!forever)
          _secondaryButton('فتح الإعدادات', Icons.settings, _openAppSettings),
      ],
    );
  }

  Widget _buildLocationDisabled() {
    return _buildStatusCard(
      icon: Icons.gps_off,
      title: 'خدمة تحديد الموقع مغلقة',
      message:
          'خدمة الموقع (GPS) مغلقة في الجهاز، وبدونها لا يمكن حساب زاوية القبلة. '
          'شغّلها من الشريط العلوي أو اضغط الزر أدناه، ثم عد إلى التطبيق.',
      actions: <Widget>[
        _primaryButton(
          'تشغيل خدمة الموقع',
          Icons.location_searching,
          _openLocationSettings,
        ),
        _secondaryButton('إعادة المحاولة', Icons.refresh, _retry),
      ],
    );
  }

  Widget _buildFailure() {
    return _buildStatusCard(
      icon: Icons.error_outline,
      title: 'تعذر الوصول إلى مستشعرات الجهاز',
      message:
          'لم نتمكن من قراءة بيانات البوصلة. تأكد من أن الجهاز يحتوي على مستشعر '
          'مغناطيسي وأنه غير معطَّل، أو أعد تشغيل التطبيق، ثم أعد المحاولة.',
      detail: _stageDetail,
      actions: <Widget>[
        _primaryButton('إعادة المحاولة', Icons.refresh, _retry),
      ],
    );
  }

  Future<void> _openAppSettings() async {
    _awaitingSettingsReturn = true;
    await LocationAccess.openAppSettings();
    // If the platform did not pause the app, no resume event will arrive, so
    // re-check straight away as well (the `_busy` guard prevents overlaps).
    if (mounted && _stage != _QiblaStage.ready) await _bootstrap();
  }

  Future<void> _openLocationSettings() async {
    _awaitingSettingsReturn = true;
    await LocationAccess.openLocationSettings();
    if (mounted) await _bootstrap();
  }

  // ---------------------------------------------------------------------------
  //  Live compass
  // ---------------------------------------------------------------------------

  Widget _buildCompassArea(bool isDark) {
    // Permissions and sensors are fine but the plugin has not produced anything
    // yet: it needs its own GPS fix before it can emit a heading.
    if (!_hasReading) return _buildWaitingForData(isDark);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Responsive dial: as large as the screen allows (never smaller than
        // 170 px, never larger than 320 px).
        final double dialSize = math.max(
          170,
          math.min(
            math.min(constraints.maxWidth - 40, constraints.maxHeight * 0.5),
            320,
          ),
        );
        final bool aligned = _isFacingQibla;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 26),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (_streamError != null) ...<Widget>[
                  _buildStreamErrorBanner(isDark),
                  const SizedBox(height: 12),
                ],
                if (_shouldShowCalibrationHint) ...<Widget>[
                  CalibrationHintCard(
                    isDark: isDark,
                    accuracyLabel: _accuracyLabel(_sensorAccuracy),
                    onDismiss: _dismissCalibrationHint,
                  ),
                  const SizedBox(height: 14),
                ],
                if (_stageDetail != null) ...<Widget>[
                  _buildInfoBanner(isDark, _stageDetail!),
                  const SizedBox(height: 12),
                ],
                _buildHeadingReadout(isDark, aligned),
                const SizedBox(height: 6),
                _buildDial(dialSize, isDark, aligned),
                const SizedBox(height: 18),
                _buildStatusBanner(isDark, aligned),
                const SizedBox(height: 18),
                _buildDetailsFooter(isDark),
              ],
            ),
          ),
        );
      },
    );
  }

  void _dismissCalibrationHint() {
    setState(() {
      _showCalibrationHint = false;
      _accuracyWhenHintDismissed = _sensorAccuracy;
    });
  }

  Widget _buildWaitingForData(bool isDark) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox.square(
              dimension: 40,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.secondaryGold,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'جارٍ تحديد موقعك…',
              style: GoogleFonts.cairo(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : AppColors.primaryEmeraldDark,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _stageDetail ??
                  'تم منح الإذن، وننتظر أول قراءة من المستشعرات لحساب اتجاه '
                      'القبلة. تأكد من أنك في مكان مكشوف وأن الهاتف بعيد عن المعادن.',
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: 13.5,
                height: 1.7,
                color: isDark ? Colors.white70 : AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 22),
            _primaryButton('إعادة المحاولة', Icons.refresh, _retry),
          ],
        ),
      ),
    );
  }

  /// Non-blocking warning: the stream reported an error but readings are still
  /// arriving, so the compass stays usable.
  Widget _buildStreamErrorBanner(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.secondaryGold.withValues(alpha: isDark ? 0.16 : 0.12),
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
              'تعذر الوصول إلى مستشعرات الجهاز لفترة وجيزة — أعد المحاولة إذا '
              'لاحظت توقف البوصلة.',
              style: GoogleFonts.cairo(
                fontSize: 12.5,
                height: 1.5,
                color: isDark ? Colors.white70 : AppColors.textDark,
              ),
            ),
          ),
          TextButton(
            onPressed: _retry,
            child: Text(
              'إعادة',
              style: GoogleFonts.cairo(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: AppColors.secondaryGold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Informational banner (slow GPS fix, …).
  Widget _buildInfoBanner(bool isDark, String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primaryEmerald.withValues(alpha: isDark ? 0.3 : 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.info_outline,
            size: 18,
            color: AppColors.primaryEmeraldLight,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
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

  /// Big heading number + the two facts the user cares about (sensor accuracy
  /// and the absolute Qibla bearing).
  Widget _buildHeadingReadout(bool isDark, bool aligned) {
    final Color headingColor = aligned
        ? AppColors.secondaryGold
        : (isDark ? Colors.white : AppColors.primaryEmerald);

    return Column(
      children: <Widget>[
        Text(
          '${_headingTrue.toStringAsFixed(0)}°',
          style: GoogleFonts.cairo(
            fontSize: 46,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
            color: headingColor,
          ),
        ),
        Text(
          'اتجاه الهاتف من الشمال الحقيقي',
          style: GoogleFonts.cairo(
            fontSize: 12.5,
            color: isDark ? Colors.white60 : AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            // Absolute bearing, independent of how the phone is held.
            _infoChip(
              Icons.explore_outlined,
              'القبلة على زاوية ${_bearing.toStringAsFixed(0)}°',
              tint: AppColors.secondaryGold,
            ),
            _infoChip(
              Icons.compass_calibration,
              _accuracyLabel(_sensorAccuracy),
              tint: _needsCalibration
                  ? AppColors.goldDark
                  : AppColors.primaryEmeraldLight,
            ),
          ],
        ),
      ],
    );
  }

  /// The dial (rotated by the *true* heading) with the Qibla needle on top
  /// (rotated by the signed alignment error).
  Widget _buildDial(double size, bool isDark, bool aligned) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // Golden halo whenever the user is facing the Qibla.
        boxShadow: aligned
            ? <BoxShadow>[
                BoxShadow(
                  color: AppColors.secondaryGold.withValues(alpha: 0.45),
                  blurRadius: 26,
                  spreadRadius: 2,
                ),
                BoxShadow(
                  color: AppColors.secondaryGold.withValues(alpha: 0.18),
                  blurRadius: 60,
                  spreadRadius: 12,
                ),
              ]
            : <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.10),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
      ),
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            // 1. The dial. Rotating by −headingTrue keeps its north mark glued
            //    to real north: turning the phone left makes the dial turn right
            //    exactly like a physical compass card.
            Transform.rotate(
              angle: -Angles.toRadians(_headingTrue),
              child: CustomPaint(
                size: Size.square(size),
                painter: _CompassDialPainter(
                  isDark: isDark,
                  accent: AppColors.secondaryGold,
                ),
              ),
            ),
            // 2. The Qibla needle, rotated by the signed error, so it always
            //    points at the Kaaba regardless of the dial's rotation.
            Transform.rotate(
              angle: Angles.toRadians(_alignmentError),
              child: CustomPaint(
                size: Size.square(size),
                painter: _QiblaNeedlePainter(
                  isDark: isDark,
                  isAligned: aligned,
                ),
              ),
            ),
            // 3. Hub.
            _buildHub(size, isDark, aligned),
          ],
        ),
      ),
    );
  }

  Widget _buildHub(double size, bool isDark, bool aligned) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      width: size * 0.19,
      height: size * 0.19,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark ? AppColors.cardSurfaceDark : Colors.white,
        border: Border.all(
          color: aligned
              ? AppColors.secondaryGold
              : AppColors.primaryEmerald.withValues(alpha: 0.35),
          width: 2,
        ),
      ),
      alignment: Alignment.center,
      child: Text('🕋', style: TextStyle(fontSize: size * 0.085)),
    );
  }

  /// Success banner (gold, with a checkmark) or the "turn N°" instruction.
  Widget _buildStatusBanner(bool isDark, bool aligned) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      child: aligned
          ? Container(
              key: const ValueKey<String>('aligned'),
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[
                    AppColors.secondaryGold,
                    AppColors.goldLight,
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppColors.secondaryGold.withValues(alpha: 0.45),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    Icons.check_circle,
                    size: 22,
                    color: AppColors.primaryEmeraldDark,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'أنت تواجه القبلة الآن 🕋',
                    style: GoogleFonts.cairo(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryEmeraldDark,
                    ),
                  ),
                ],
              ),
            )
          : Text(
              _turnInstruction,
              key: const ValueKey<String>('turning'),
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : AppColors.primaryEmerald,
              ),
            ),
    );
  }

  /// Distance to the Kaaba, magnetic declination and the raw (magnetic) sensor
  /// heading — the numbers that explain *why* the needle sits where it does.
  Widget _buildDetailsFooter(bool isDark) {
    final double? distance = _distanceToKaabaKm;

    return Column(
      children: <Widget>[
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            if (distance != null)
              _infoChip(
                Icons.straighten,
                'المسافة إلى الكعبة ${distance.toStringAsFixed(0)} كم',
              ),
            _infoChip(
              Icons.public,
              'الانحراف المغناطيسي '
              '${_declination >= 0 ? '+' : '−'}${_declination.abs().toStringAsFixed(1)}°',
            ),
            _infoChip(
              Icons.screen_rotation,
              'قراءة المستشعر ${_headingMagnetic.toStringAsFixed(0)}°',
            ),
          ],
        ),
        if (_latitude != null && _longitude != null) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            'خط العرض ${_latitude!.toStringAsFixed(3)} · '
            'خط الطول ${_longitude!.toStringAsFixed(3)}',
            style: GoogleFonts.cairo(
              fontSize: 10.5,
              color: isDark ? Colors.white38 : AppColors.textMuted,
            ),
          ),
        ],
      ],
    );
  }

  Widget _infoChip(IconData icon, String label, {Color? tint}) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color color =
        tint ?? (isDark ? Colors.white70 : AppColors.primaryEmerald);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.cairo(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
//  Painters
// -----------------------------------------------------------------------------

/// The compass card: ticks, degree numbers and the four Arabic cardinal points.
///
/// The whole painter is rotated by `−headingTrue`, so "north" here means *true*
/// north on the horizon; the painter itself always draws north at the top.
class _CompassDialPainter extends CustomPainter {
  const _CompassDialPainter({required this.isDark, required this.accent});

  final bool isDark;
  final Color accent;

  /// Point on the dial for a bearing `degrees` (0° = up/north, clockwise).
  ///
  /// Canvas Y grows downwards, hence the `sin` for X and `−cos` for Y.
  static Offset _polar(Offset center, double degrees, double radius) {
    final double radians = Angles.toRadians(degrees);
    return center +
        Offset(math.sin(radians) * radius, -math.cos(radians) * radius);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = size.shortestSide / 2;

    final Color faceColor = isDark ? AppColors.cardSurfaceDark : Colors.white;
    final Color majorTickColor = isDark ? Colors.white30 : Colors.black26;
    final Color minorTickColor = isDark ? Colors.white12 : Colors.black12;
    final Color ringColor = isDark
        ? Colors.white.withValues(alpha: 0.18)
        : AppColors.primaryEmerald.withValues(alpha: 0.22);

    // Face, outer ring and a hairline inner circle.
    canvas.drawCircle(center, radius - 1, Paint()..color = faceColor);
    canvas.drawCircle(
      center,
      radius - 2,
      Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      center,
      radius * 0.70,
      Paint()
        ..color = ringColor.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Ticks: every 5°, longer every 15°, longest (and gold) on the 4 cardinal
    // points.
    for (int degree = 0; degree < 360; degree += 5) {
      final bool isCardinal = degree % 90 == 0;
      final bool isMajor = degree % 15 == 0;
      final double outer = radius * 0.94;
      final double inner = outer -
          (isCardinal
              ? radius * 0.11
              : (isMajor ? radius * 0.07 : radius * 0.035));

      canvas.drawLine(
        _polar(center, degree.toDouble(), inner),
        _polar(center, degree.toDouble(), outer),
        Paint()
          ..color =
              isCardinal ? accent : (isMajor ? majorTickColor : minorTickColor)
          ..strokeCap = StrokeCap.round
          ..strokeWidth = isCardinal ? 3 : (isMajor ? 2 : 1),
      );
    }

    // Degree numbers every 30° (the cardinal points get a word instead).
    final TextStyle numberStyle = GoogleFonts.cairo(
      fontSize: radius * 0.085,
      fontWeight: FontWeight.w600,
      color: isDark ? Colors.white38 : AppColors.textMuted,
    );
    for (int degree = 0; degree < 360; degree += 30) {
      if (degree % 90 == 0) continue;
      _paintCenteredText(
        canvas,
        '$degree',
        numberStyle,
        _polar(center, degree.toDouble(), radius * 0.78),
      );
    }

    // Cardinal points in Arabic. Full words are used on purpose: the
    // abbreviations of شمال and شرق would both be «ش».
    const Map<int, String> cardinals = <int, String>{
      0: 'شمال',
      90: 'شرق',
      180: 'جنوب',
      270: 'غرب',
    };
    cardinals.forEach((int degree, String label) {
      final bool isNorth = degree == 0;
      _paintCenteredText(
        canvas,
        label,
        GoogleFonts.cairo(
          fontSize: radius * (isNorth ? 0.115 : 0.10),
          fontWeight: FontWeight.bold,
          color: isNorth
              ? accent
              : (isDark ? Colors.white70 : AppColors.primaryEmeraldDark),
        ),
        _polar(center, degree.toDouble(), radius * 0.80),
      );
    });
  }

  @override
  bool shouldRepaint(_CompassDialPainter oldDelegate) =>
      oldDelegate.isDark != isDark || oldDelegate.accent != accent;
}

/// The Qibla needle, drawn pointing straight up (north of the widget) so the
/// caller can simply rotate it by the signed alignment error.
class _QiblaNeedlePainter extends CustomPainter {
  const _QiblaNeedlePainter({required this.isDark, required this.isAligned});

  final bool isDark;
  final bool isAligned;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = size.shortestSide / 2;
    final Color needleColor = isAligned
        ? AppColors.secondaryGold
        : (isDark ? Colors.white : AppColors.primaryEmerald);

    // Golden halo while the device points at the Kaaba.
    if (isAligned) {
      canvas.drawCircle(
        center,
        radius * 0.88,
        Paint()
          ..color = AppColors.secondaryGold.withValues(alpha: 0.30)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
      );
    }

    // Needle: a slim triangle from the hub up to just inside the rim.
    final double tip = center.dy - radius * 0.78;
    final double base = center.dy - radius * 0.10;
    final double halfWidth = radius * 0.07;
    canvas.drawPath(
      Path()
        ..moveTo(center.dx, tip)
        ..lineTo(center.dx - halfWidth, base)
        ..lineTo(center.dx + halfWidth, base)
        ..close(),
      Paint()..color = needleColor,
    );

    // Mirrored, translucent tail so the needle looks anchored in the hub.
    canvas.drawPath(
      Path()
        ..moveTo(center.dx, center.dy + radius * 0.30)
        ..lineTo(center.dx - halfWidth * 0.65, center.dy + radius * 0.04)
        ..lineTo(center.dx + halfWidth * 0.65, center.dy + radius * 0.04)
        ..close(),
      Paint()..color = needleColor.withValues(alpha: 0.45),
    );

    // Gold cap on the Qibla end.
    canvas.drawCircle(
      Offset(center.dx, tip),
      radius * 0.045,
      Paint()..color = isAligned ? Colors.white : AppColors.secondaryGold,
    );
  }

  @override
  bool shouldRepaint(_QiblaNeedlePainter oldDelegate) =>
      oldDelegate.isAligned != isAligned || oldDelegate.isDark != isDark;
}

// -----------------------------------------------------------------------------
//  Calibration hint (animated "figure-8")
// -----------------------------------------------------------------------------

/// Dismissible reminder that shows the animated ∞ motion used to calibrate the
/// magnetometer. Re-appears automatically when the sensor accuracy drops again.
class CalibrationHintCard extends StatefulWidget {
  const CalibrationHintCard({
    super.key,
    required this.isDark,
    required this.accuracyLabel,
    required this.onDismiss,
  });

  final bool isDark;

  /// Text describing the current magnetometer accuracy (see `_accuracyLabel`).
  final String accuracyLabel;

  final VoidCallback onDismiss;

  @override
  State<CalibrationHintCard> createState() => _CalibrationHintCardState();
}

class _CalibrationHintCardState extends State<CalibrationHintCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      decoration: BoxDecoration(
        color: AppColors.primaryEmerald.withValues(
          alpha: widget.isDark ? 0.35 : 0.08,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.secondaryGold.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: <Widget>[
          SizedBox.square(
            dimension: 46,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (BuildContext context, Widget? child) {
                return CustomPaint(
                  painter: _Figure8Painter(
                    progress: _controller.value,
                    color: AppColors.secondaryGold,
                    markerColor: AppColors.goldDark,
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'لمزيد من الدقة: حرّك الهاتف على شكل الرقم 8',
                  style: GoogleFonts.cairo(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: widget.isDark
                        ? Colors.white
                        : AppColors.primaryEmeraldDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'هذه الحركة تعاير البوصلة بعيداً عن المعادن (${widget.accuracyLabel}).',
                  style: GoogleFonts.cairo(
                    fontSize: 11.5,
                    height: 1.5,
                    color: widget.isDark ? Colors.white70 : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'إخفاء',
            onPressed: widget.onDismiss,
            icon: Icon(
              Icons.close,
              size: 18,
              color: widget.isDark ? Colors.white54 : AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Draws the classic figure-8 (∞) calibration path with a marker travelling
/// along it. The curve is the lemniscate of Gerono:
///
///     x = a · cos t ,   y = b · sin(2t) / 2
class _Figure8Painter extends CustomPainter {
  const _Figure8Painter({
    required this.progress,
    required this.color,
    required this.markerColor,
  });

  /// Animation position, 0 → 1.
  final double progress;
  final Color color;
  final Color markerColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double a = size.width / 2 - 5;
    final double b = size.height / 2 - 5;

    Offset pointOnCurve(double t) =>
        center + Offset(a * math.cos(t), b * math.sin(2 * t) / 2);

    const int steps = 64;
    final Path path = Path()..moveTo(pointOnCurve(0).dx, pointOnCurve(0).dy);
    for (int i = 1; i <= steps; i++) {
      final Offset point = pointOnCurve(2 * math.pi * i / steps);
      path.lineTo(point.dx, point.dy);
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    // Marker travelling along the path.
    final Offset marker = pointOnCurve(2 * math.pi * progress);
    canvas.drawCircle(
        marker, 4.5, Paint()..color = color.withValues(alpha: 0.25));
    canvas.drawCircle(marker, 2.6, Paint()..color = markerColor);
  }

  @override
  bool shouldRepaint(_Figure8Painter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
