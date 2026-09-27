# Debug report — صلاة-السعدية (salat_al_saadia)

**Scope:** whole app (`lib/`, `test/`, `pubspec.yaml`, `AndroidManifest.xml`), with the
Qibla compass as the primary target.
**Date:** 2026-09-26 · **Flutter** 3.47.2 stable · **Dart** 3.13.2 · Windows 10 (host), Android target.
**Method:** static audit of every feature file → targeted greps for lifecycle/resource
bugs → numeric cross-check of the compass maths against the plugin's own algorithm and
published Qibla bearings → permanent regression suite in `test/qibla_math_test.dart`
→ `dart format` + `flutter analyze` + `flutter test`.

---

## 1. Executive summary

The compass now works for the right reasons: the location permission is actually
requested at runtime, the heading is converted from magnetic to **true** north with the
World Magnetic Model, the bearing is computed with `atan2` (correct in every quadrant),
and the "aligned" test is done on a **normalised** angle. Before, none of the four was
true, so the needle could not be correct anywhere on Earth and the success state could
never activate.

| # | Sev | Area | Issue | Status |
|---|-----|------|-------|--------|
| Q-1 | **Critical** | Qibla | `ACCESS_FINE_LOCATION` was never requested at runtime → the plugin never got a position → no Qibla direction at all (only a generic error) | Fixed |
| Q-2 | **Critical** | Qibla | Alignment test used the raw, unnormalised `qibla.qiblah` (can be 400°+) → `abs() < 3` was never true | Fixed + tested |
| Q-3 | **High** | Qibla | Magnetic azimuth used as if it were true north → needle off by the local declination (≈ +4° Egypt, ±13° North America) | Fixed + tested |
| Q-4 | **High** | Qibla | No sensor calibration path; no clue that the magnetometer was uncalibrated | Fixed |
| Q-5 | **Medium** | Qibla | Bearing from the plugin's `atan()` + quadrant heuristics; returns unnormalised negatives in the southern/western hemisphere | Replaced with `atan2` + parity test |
| Q-6 | **Medium** | Qibla | Stream errors and permission failures produced one generic Arabic sentence and no way to recover | Fixed |
| Q-7 | **Medium** | App shell | `IndexedStack` mounts all 5 tabs at launch → the location dialog popped up on the *prayer-times* tab, before the user ever opened Qibla | Fixed (TickerMode gating) |
| Q-8 | **Medium** | Qibla | Returning from Settings popped the permission dialog again on every resume (possible loop) | Fixed |
| Q-9 | **Medium** | Qibla | Magnetometer + a repeating 60 fps animation ran while the tab was hidden (battery) | Fixed |
| Q-10 | **Medium** | Quran reader | Every Ayah number marker was rendered *before* the text instead of between the Ayahs | Fixed |
| Q-11 | **Medium** | App start | `QuranFonts.ensureLoaded()` and `QuranAudioController.configureAudioSession()` were documented "call from `main()`" but never called (dead code, no audio-session config) | Fixed |
| Q-12 | **Low** | Assets | `assets/fonts/` referenced by code and docs but missing and not registered in `pubspec.yaml` → the documented font drop-in could never work | Fixed |
| Q-13 | **Low** | Prayer times | Stray unused class `NeverScrollableScrollFitEmpty` at the end of the screen file | Removed |
| Q-14 | **Info** | Tooling | `dart format` re-wrapped 15 files (whitespace only) — see §5 | Disclosed |
| Q-15 | **Info** | Prayer times | Screen is still hard-coded mock data (`adhan`, notifications, `timezone` are unused) | Reported, not implemented |
| Q-16 | **Info** | Dependencies | `permission_handler` intentionally not added — see §7 | Decision |

**Verification:** `flutter analyze lib test` → *No issues found* · `flutter test` → *23/23 passed*
· `flutter pub get` → *Got dependencies* · all 16 Material icons checked against the SDK
· bearing cross-checked for 20 cities (max delta vs. the plugin's own formula: **0.005°**).

---

## 2. Environment blocker (pre-existing, must be resolved to build)

`pubspec.yaml` overrides `flutter_qiblah` / `flutter_compass_v2` with **local patched
copies** at `../flutter_qiblah_local` and `../flutter_compass_v2_local`. Neither folder
exists anywhere on this machine, so:

* `flutter pub get`, `flutter analyze` and `flutter test` fail with 7 errors
  (`Target of URI doesn't exist: 'package:flutter_qiblah/flutter_qiblah.dart'`, …);
* `flutter build apk` cannot run at all.

This is unrelated to the compass logic (the previous implementation had it too).

For the verification runs in this report I temporarily created two directory junctions
to the **byte-identical Dart sources** in the pub cache (only the Android build files
differ between the patched copies and the published ones), ran everything, and then
removed the junctions again — your workspace is back to its original state.

To get a buildable tree:

```powershell
# 1. Restore the patched copies (preferred) — see BUILD_NOTES.md §1:
#    no private buildscript/classpath, no jcenter, compileSdk 36,
#    modern lint {}/kotlin { compilerOptions { … } } blocks, no package= in the manifest.
#    Expected layout:  ..\flutter_qiblah_local\  ..\flutter_compass_v2_local\

# 2. Or, TEMPORARY stopgap just to run analyze/tests (NOT for building an APK —
#    the published Android build files break AGP 9, and a junction must never be
#    deleted with `Remove-Item -Recurse` because that can follow it into the cache):
New-Item -ItemType Junction -Path "..\flutter_qiblah_local"     -Target "$env:LOCALAPPDATA\Pub\Cache\hosted\pub.dev\flutter_qiblah-3.2.0"
New-Item -ItemType Junction -Path "..\flutter_compass_v2_local" -Target "$env:LOCALAPPDATA\Pub\Cache\hosted\pub.dev\flutter_compass_v2-1.0.3"
```

---

## 3. Findings — Qibla compass

### Q-1 · Critical · The location permission was never requested
*File:* `lib/features/qibla/presentation/screens/qibla_screen.dart` (old version)
*Symptom:* the screen sat on "تعذر جلب بيانات البوصلة" or a spinner forever.
*Root cause:* `FlutterQiblah.qiblahStream` merges the compass with
`Geolocator.getPositionStream()`. Since Android 6 the `ACCESS_FINE_LOCATION` manifest
entry alone is not enough — a **runtime** request is required. Nothing ever asked, so the
position stream errored, `combineLatest` never produced a value and the Qibla angle was
never computed.
*Fix:* `_bootstrap()` runs `FlutterQiblah.androidDeviceSensorSupport()` →
`LocationAccess.ensureAccess()` (service check → permission → high-accuracy fix with a
20 s timeout) → position-derived maths, and maps each outcome to its own UI state
(`unsupported`, `permissionDenied`, `permissionDeniedForever`, `locationDisabled`,
`timedOut`, `failed`).

### Q-2 · Critical · The alignment test could never be true
*Root cause:* `flutter_qiblah` builds `QiblahDirection.qiblah` as
`heading + (360 − offset)` where `offset` comes from an unnormalised `atan()` (Sydney
→ −82.5°). The old code tested `qibla.qiblah.abs() < 3` on that raw value — for Sydney
it reads **720°**, so `abs() < 3` was false even when the phone was perfectly aligned.
*Fix:* the relative angle is now `Angles.difference(trueHeading, bearing)` →
`normalize180(...)`, i.e. always in (−180°, 180°]; the ±3° window is applied to that.
*Tested:* `the plugin offset is NOT normalised (the original bug)` +
`inside the window is aligned, outside is not`.

### Q-3 · High · Magnetic north was used as true north
*Root cause:* `flutter_compass_v2` reports the **magnetic** azimuth
(`MathUtils.calculateAzimuth`, see the Android source; the plugin ships a
declination helper but never calls it). The Qibla bearing is relative to **true** north,
so every reading was wrong by the local declination `δ`.
*Fix:* `magneticDeclination()` (World Magnetic Model, `geomag`) is applied once per
position: `headingTrue = normalize360(direction + δ)`. The dial follows `headingTrue`,
and the relative error is computed against `bearingTrue`. `δ` is shown in the footer
("الانحراف المغناطيسي +4.0°") so the correction is auditable on the device.
*Tested:* sign/magnitude bounds for Cairo (+), New York (−) and Sydney (+).

### Q-4 · High · No calibration path
*Symptom:* users tilt the phone and the needle lags or drifts, with no hint why.
*Fix:* a dismissible card at the top with an animated figure-8 cue (lemniscate of Gerono,
`_Figure8Painter`) and the current accuracy in words. It is driven by the magnetometer
accuracy that Android reports (15/30/45°/unknown via `FlutterCompass.events`) and
re-arms itself when accuracy degrades after dismissal.

### Q-5 · Medium · `atan()` + quadrant heuristics instead of `atan2`
*Root cause:* the plugin's `Utils.getOffsetFromNorth` → unnormalised, negative values in
the southern hemisphere / western longitudes.
*Fix:* `trueBearingToKaaba()` uses the great-circle initial bearing with `atan2`
(correct quadrant by construction) and the app's own Kaaba constants.
*Tested:* parity with the plugin for 12 cities — **max delta 0.005°** — plus an explicit
"never negative" test for Sydney/Jakarta/Honolulu.

### Q-6 · Medium · One-size-fits-all error handling
*Fix:* six distinct states with their own copy, a device-support check, a non-blocking
banner when the stream reports an error while readings still flow, a warning + retry when
the GPS fix times out (the heading keeps working, and the plugin's `offset` is used as
the bearing fallback), and "إعادة المحاولة" in the AppBar as well as on every failure
card (`_retry()` calls `FlutterQiblah().dispose()` so the cached stream is rebuilt).

### Q-7 · Medium · Permission dialog on the wrong tab at launch
*Root cause:* `MainNavigationScreen` uses an `IndexedStack`, which **mounts all five
tabs** immediately; the default tab is المواقيت, but `QiblaScreen.initState` already ran
the permission flow, so the system dialog appeared while the user was looking at the
prayer times.
*Fix:* the shell now wraps each tab in `TickerMode(enabled: i == currentIndex)`, and
`QiblaScreen.didChangeDependencies()` reads `TickerMode.valuesOf(context).enabled`:
first visit → full bootstrap; later visits → resume the stream directly (no spinner);
hidden → `_stopStream()`.
*Bonus:* hidden tabs no longer animate (the calibration cue and any other repeating
animation stop consuming frames off screen).

### Q-8 · Medium · Possible permission-dialog loop
*Root cause:* the resume handler re-ran the whole bootstrap whenever the screen was not
`ready`, and on Android each resume after a plain "deny" re-opens the system dialog.
*Fix:* resume only re-checks when it is meaningful — the user came back from Settings
(`_awaitingSettingsReturn`) or the state is `permissionDeniedForever` /
`locationDisabled`. A plain "denied" is fixed from an explicit in-app button.

### Q-9 · Medium · Battery: sensors and a 60 fps animation while hidden
*Fix:* covered by Q-7 (ticker muted + magnetometer released off screen). Repaints are
also throttled to a ≥ 0.5° heading change, so the ~30 Hz sensor stream no longer forces
30 rebuilds/second of 36 ticks + 12 text painters.

---

## 4. Findings — other features (found while auditing "everything")

### Q-10 · Medium · Quran reader rendered all Ayah markers before the text
*File:* `lib/features/quran/presentation/screens/surah_screen.dart`
*Symptom:* opening a Surah showed a long row of numbered circles at the top, then the
whole Surah text — the markers were not between the Ayahs as the doc comment promised
(tapping them still played the right Ayah, so this was purely a layout bug).
*Root cause:* the `TextSpan.children` list emitted a `WidgetSpan` for every Ayah first and
then one `TextSpan(text: verses.join(' '))`.
*Fix:* the loop now emits `TextSpan(verse)` + `WidgetSpan(marker)` per Ayah, mushaf style.

### Q-11 · Medium · Two documented initialisers were never called
*File:* `lib/main.dart`
*Root cause:* `QuranFonts.ensureLoaded()` ("call it from `main()` before `runApp()` so the
first frame already uses the right typeface") and
`QuranAudioController.configureAudioSession()` ("Call it from `main()`: it makes the
recitation duck/pause correctly when a phone call or another media app starts") were dead
code — nothing called them, so the bundled-font pipeline was never exercised and the
player ran with `just_audio`'s default session instead of a spoken-word one.
*Fix:* `main()` is now `async`, awaits `QuranFonts.ensureLoaded()` and
`configureAudioSession()` (wrapped in `try/catch`, never blocks start-up).

### Q-12 · Low · The font drop-in path could not work
*Root cause:* `QuranFonts.bundledFontAssets` lists `assets/fonts/*.ttf` and its doc
comment points at `assets/fonts/README.md`, but the folder did not exist and was not
listed under `flutter.assets` — so even a font dropped in place would not have been
bundled.
*Fix:* created `assets/fonts/README.md` (source links + the exact file names that are
detected) and registered `- assets/fonts/` in `pubspec.yaml`. `flutter pub get` still
resolves fine; if no font file is present the app keeps falling back to Google Fonts
"Amiri Quran" exactly as before.

### Q-13 · Low · Dead code removed
`lib/features/prayer_times/presentation/screens/prayer_times_screen.dart` ended with an
unused `NeverScrollableScrollFitEmpty extends ScrollPhysics` class. Removed.

### Q-14 · Info · `dart format` run
`dart format lib test` was executed as part of debugging and re-wrapped **15 files**
(line breaks/indentation only — `dart format` is AST based, and `flutter analyze` +
`flutter test` are green afterwards). Ten of them carry no other change; two
(`prayer_times_screen.dart`, `surah_screen.dart`) also carry the fixes above. If you
prefer a minimal diff, restore those files from your VCS/backup and keep the intentional
edits listed in §6. Files touched: `core/constants/app_typography.dart`,
`core/fonts/quran_fonts.dart`, `core/location/location_access.dart`,
`core/utils/angles.dart`, `features/adhkar/…/adhkar_screen.dart`,
`features/adhkar/…/adhkar_counter_card.dart`, `features/prayer_times/…`,
`features/quran/data/quran_audio_player.dart`, `…/quran_audio_state.dart`,
`…/quran_data.dart`, `features/quran/presentation/screens/quran_screen.dart`,
`…/surah_screen.dart`, `features/quran/presentation/widgets/quran_audio_bar.dart`,
`features/tasbeeh/…/tasbeeh_controller.dart`, `features/tasbeeh/…/tasbeeh_screen.dart`.

### Q-15 · Info · Prayer times screen is still mock UI (not a regression)
`prayer_times_screen.dart` shows hard-coded names/times and a frozen countdown, while
`adhan`, `flutter_local_notifications` and `timezone` are already declared. Nothing in
this debug pass broke it, but it is the largest remaining feature gap.
*Recommendation:* compute with `adhan` from the position `LocationAccess` already
provides, cache per day, schedule notifications, and drive the banner from a `Timer`
that is cancelled in `dispose()`.

### Q-16 · Info · Minor observations (no action taken)
* `AdhkarCounterCard` calls `Vibration.vibrate()` without the `hasVibrator()` guard used
  by the Tasbeeh controller (it is inside `try/catch`, so it is safe — just inconsistent).
* `README.md` still lists `audioplayers` for the Quran tab; the code uses `just_audio`.
* `README.md`/`BUILD_NOTES.md` claim `flutter analyze` is clean — that is true again now,
  but only once the plugin overrides in §2 are restored.
* `analysis_options.yaml` has an empty `rules:` block (harmless).

---

## 5. Verification log (all commands run on this machine)

| # | Command | Result |
|---|---------|--------|
| 1 | `flutter --version` | Flutter 3.47.2 · Dart 3.13.2 |
| 2 | `flutter pub get` | Got dependencies (with `- assets/fonts/` added) |
| 3 | `flutter analyze lib test` | **No issues found** (3 s) |
| 4 | `flutter test test/qibla_math_test.dart` | **23 tests, all passed** (exit 0) |
| 5 | `dart format lib test` | 22 files, 15 re-wrapped (see Q-14) |
| 6 | Bearing cross-check (20 coordinates, our `atan2` vs. the plugin's `atan`) | max delta **0.005°** for real locations |
| 7 | Bearing vs. published tables (12 cities) | **< 0.05°** each |
| 8 | Magnetic icons check (16 `Icons.*` names against the SDK) | all exist |
| 9 | Alignment chain in Cairo: `direction` 60° (magnetic) + δ → true 64.3°; bearing 136.14°; error **+71.84°** (turn right) | correct sign/convention |
| 10 | Facing check: heading = bearing → error **0.000000** → aligned | ±3° window works |
| 11 | Wrap check: `Angles.difference(359, 1)` = **2.00** (old code: 358) | fixed |

Test suite contents (`test/qibla_math_test.dart`):

* 12 × "matches the published bearing" (Cairo, Riyadh, London, New York, Sydney, Jakarta,
  Tokyo, Los Angeles, Nairobi, Istanbul, Moscow, Cape Town)
* "is always normalised, even in the southern/western hemisphere"
* "agrees with flutter_qiblah's own formula for real locations"
* "the plugin offset is NOT normalised (the original bug)"
* 3 × alignment window (±3°, turn direction, zero error)
* 2 × `Angles` normalisation (short arc, negatives/overflow/NaN)
* 2 × magnetic declination (signed value, no throw at the poles)
* 1 × Kaaba distance

Run them with:

```bash
flutter test test/qibla_math_test.dart
# or the whole suite (only this file exists today):
flutter test
```

---

## 6. Files changed

| File | Change |
|------|--------|
| `lib/features/qibla/presentation/screens/qibla_screen.dart` | Rewritten (1 597 lines): permission/sensor bootstrap, true-north + declination, `atan2` bearing, six UI states, calibration card, custom dial/needle/∞ painters, dark mode, haptics, throttled repaints, TickerMode visibility gating |
| `lib/features/home/presentation/main_navigation_screen.dart` | Tabs wrapped in `TickerMode(enabled: i == currentIndex)` (visibility signal + no off-screen animation) |
| `lib/main.dart` | `async main()` + `QuranFonts.ensureLoaded()` + `configureAudioSession()` |
| `lib/features/quran/presentation/screens/surah_screen.dart` | Ayah markers interleaved with the Ayah text |
| `lib/features/prayer_times/presentation/screens/prayer_times_screen.dart` | Dead `NeverScrollableScrollFitEmpty` class removed |
| `android/app/src/main/AndroidManifest.xml` | Added optional-hardware declarations (`sensor.compass`, `location.gps`, `required="false"`); the two location permissions were already present |
| `pubspec.yaml` | `- assets/fonts/` registered (no new package needed) |
| `assets/fonts/README.md` | New: where to get Uthman Taha Naskh / Amiri Quran + the file names detected |
| `test/qibla_math_test.dart` | New: 23 assertion groups that lock the compass maths down |
| `DEBUG_REPORT.md` | This report |

No dependency was added or removed. `permission_handler` stays out on purpose: the
project's own `LocationAccess` wrapper (geolocator) already performs the exact
`ACCESS_FINE_LOCATION` runtime request, handles `deniedForever`, the GPS toggle and
`openAppSettings()`, and is shared with the prayer-times feature — a second permission
plugin would duplicate that flow. If you want it anyway:

```bash
flutter pub add permission_handler
# then in _bootstrap(): replace LocationAccess.ensureAccess() with
#   await Permission.location.request()  (and check .isPermanentlyDenied / .isGranted)
# and LocationAccess.openAppSettings() with openAppSettings()
```

<!-- CHUNK -->
