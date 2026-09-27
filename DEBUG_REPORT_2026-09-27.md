# Debug report — صلاة-السعدية (salat_al_saadia)

> **Second pass — 2026-09-27.** The 2026-09-26 pass (Qibla compass) is summarised in
> the appendix at the bottom. This pass audited the **remaining** four features and
> the build configuration.

**Scope:** every Dart source file in `lib/` (18 files), `test/`, `pubspec.yaml`,
`android/app/src/main/AndroidManifest.xml`, and the asset tree.
**Date:** 2026-09-27 · **Flutter** 3.47.2 stable · **Dart** 3.13.2 · Windows 11 (host), Android target.
**Method:** full read of every source file → `flutter analyze lib test` →
`flutter test` → targeted numeric cross-checks against published references →
new regression suites in `test/quran_data_test.dart` and `test/prayer_times_test.dart`.

**Result:** `flutter analyze lib test` → **No issues found** · `flutter test` → **41/41 passed**
(23 pre-existing Qibla maths + 18 new).

---

## 1. Executive summary

The previous pass fixed the Qibla compass. This pass audited the other four
features and the build configuration, and found the same class of problem the
Qibla screen used to have: **UI that looks finished but is not connected to
anything real.**

The headline finding is the **prayer-times screen**. It was 100 % hard-coded
mock data — six fixed strings (`"05:12 AM"`), a hard-coded
`"الصلاة القادمة: الظهر"`, and a frozen `"01:42:15"` countdown that never ticked,
in an app whose entire purpose is telling a Muslim when to pray. `adhan` was
already a declared dependency and was never imported anywhere. That screen is
now a real feature, backed by a tested controller.

The second theme is **the mushaf reader recomputing 6 236 Ayah counts on every
keystroke.** `globalAyahNumber` was an O(n) loop called once per Ayah inside
`build()`, so tapping the font-size button on Al-Baqarah performed ~32 000
dataset lookups and rebuilt the whole page. It is now an O(1) prefix-sum table.

Nine defects were fixed and four were deliberately left alone (documented in §5).

| # | Sev | Area | Issue | Status |
|---|-----|------|-------|--------|
| P-1 | **Critical** | Prayer times | The entire screen was hard-coded mock data; `adhan` was declared but never imported. The countdown was a frozen literal | **Fixed** (real feature) |
| P-2 | **High** | Prayer times | No location/permission handling → a real implementation had to add the `ACCESS_FINE_LOCATION` flow or it would show nothing | Fixed (reuses `LocationAccess`) |
| P-3 | **High** | Quran reader | `globalAyahNumber` was O(surah) and called per Ayah inside `build()` → ~32 000 dataset scans per rebuild of Al-Baqarah | Fixed (O(1) prefix sum) + tested |
| P-4 | **High** | Quran reader | Out-of-range (surah, ayah) input produced a URL/marker for a non-existent track | Fixed (clamped) + tested |
| P-5 | **Medium** | Quran audio | The URL builders ignored each reciter's capabilities, so an unsupported edition produced a guaranteed 404 | Fixed (`null` + Arabic message) + tested |
| P-6 | **Medium** | Quran audio | `selectReciter` persisted the choice *before* validating it, so an invalid pick broke the other playback layout later | Fixed |
| P-7 | **Medium** | Quran reader | The Surah screen's reciter menu always offered Surah-only editions, even mid-Ayah playback | Fixed (mode-aware) |
| P-8 | **Medium** | Prayer times | After Isha, every prayer is in the past → an empty/"—" countdown for the whole pre-dawn hour | Fixed (targets tomorrow's Fajr) |
| P-9 | **Medium** | Qibla | A retry whose GPS fix timed out kept the *previous* bearing and declination, silently pointing the needle at the Kaaba as seen from the old location | Fixed |

---

## 2. What was wrong, in detail

### P-1 · Critical · The prayer-times screen was fake

The old `prayer_times_screen.dart` was a `StatelessWidget` containing a literal
`List<Map<String, dynamic>>`:

```dart
final prayers = [
  {"name": "الفجر", "time": "05:12 AM", "passed": true},
  ...
  {"name": "الظهر", "time": "12:28 PM", "current": true},
];
```

…and a hard-coded banner: `'الصلاة القادمة: الظهر'` above the literal string
`'01:42:15'`. The same six times were shown to every user in every country, on
every day, and the countdown never moved. `adhan` was in `pubspec.yaml` but
`grep` over `lib/` found **zero** imports of it.

**Fix — the screen is now a real feature** (`prayer_times_controller.dart`, new):

* Times are computed with `adhan.PrayerTimes` from the device's real GPS
  position, reusing the existing `LocationAccess` wrapper (so the Qibla screen's
  permission flow is shared, not duplicated).
* Five calculation conventions are offered (Egyptian — the default, Umm al-Qura,
  Muslim World League, Karachi, ISNA) via a dropdown; switching one recomputes.
* A **live `HH:MM:SS` countdown** driven by a 1 Hz `Timer`.
* The timetable is computed **once per day** and cached; only the countdown
  updates per tick, so six prayer rows are not rebuilt every second.
* Midnight rollover is detected and the timetable is recomputed, so the app left
  open overnight does not show yesterday's times.
* The countdown reaching zero advances "current/next" once rather than
  recomputing on every tick.
* The ticker is cancelled in `ref.onDispose`, and a `_disposed` flag stops the
  in-flight `refresh()` from writing to a dead notifier (`Notifier`'s `ref` has
  no `mounted` getter — that was a real compile error, see §4).
* No GPS fix → the screen still works, falling back to Cairo coordinates with a
  visible Arabic note saying so, rather than showing an error screen.
* Times render as 24-hour `HH:MM`. The old `"12:28 PM"` inside a
  `TextDirection.rtl` layout is ambiguous at best.

The banner's next-prayer logic deliberately **excludes sunrise**
(`AppPrayer.isPrayer`): sunrise is a reference time, not a prayer, and the naive
implementation would have had the countdown stop there every morning.

### P-2 · High · Permission flow

A real implementation needs `ACCESS_FINE_LOCATION`. Rather than add a second
permission plugin, the controller calls the project's own
`LocationAccess.ensureAccess()`, which already performs the exact runtime request
Android 6+ needs and distinguishes *denied* / *denied forever* / *GPS off* /
*timeout*. Permission failures surface as a non-blocking banner **above a still
usable timetable**; a bare GPS timeout does not, because the Cairo fallback is
coherent.

### P-3 · High · O(n²) mushaf reader

```dart
// before
int globalAyahNumber(int surahNumber, int verseNumber) {
  int running = 0;
  for (int surah = 1; surah < surahNumber; surah++) {
    running += quran.getVerseCount(surah);   // a dataset lookup, per iteration
  }
  return running + verseNumber;
}
```

`SurahScreen` calls this **once per Ayah, inside `build()`**. Al-Baqarah (286
Ayahs) therefore ran 286 × ~113 dataset lookups ≈ **32 000** on every rebuild —
and the screen rebuilds on every tap of the A−/A+ font buttons. Opening the
longest Surah could visibly stutter.

**Fix:** a lazily built prefix-sum table (`_offsets`), so the call is O(1) and
the table is built at most once per `QuranRepository` instance. A sanity guard
falls back to the slow path if the dataset's total ever disagrees with 6 236, so
a future `quran` release cannot silently corrupt the numbering.

### P-4 · High · Unvalidated indices

The same function would happily return 700+ for a bad index, producing a CDN
URL for a track that does not exist and an Ayah marker that lies. Surah and Ayah
are now clamped to the valid range. Locked down by a test that walks **all 6 236
Ayahs** and asserts the numbering is exactly 1…6236 with no gap or duplicate.

| P-10 | **Medium** | Prayer times | `adhan` throws (`NaN`) inside the polar circles — an unhandled crash for users above ~66° N/S | Fixed (guarded, explained) |
| P-11 | **Medium** | Prayer times | `PrayerTimesScreen` was a `StatelessWidget`; a live countdown needs a `Timer` that must be cancelled | By design (`ref.onDispose`-guarded) |
| P-12 | **Low** | Quran audio | `_fail` always prefixed a generic "playback failed / check your internet" string, even for non-network errors | Fixed (optional message) |
| P-13 | **Info** | `pubspec.yaml` | `flutter_svg`, `shared_preferences`, `intl`, `flutter_local_notifications` and `timezone` are declared but never imported | Reported, not removed |
| P-14 | **Info** | `pubspec.yaml` | `assets/images/` and `assets/audio/` are registered but empty | Reported |
| P-15 | **Info** | `pubspec.yaml` | A UTF-8 BOM precedes `name:` (pre-existing; `pub` tolerates it) | Reported |
| P-16 | **Info** | Tooling | `flutter analyze`'s char-code rule flags the BOM in `pubspec.yaml` and the generated `MainActivity.kt` | Disclosed |


### P-5/P-6/P-7 · Medium · Reciter editions vs. playback layout

`QuranReciter` already documented that the CDN does not serve every edition in
both layouts (`surahAudio` / `verseAudio` flags), and both menus were mode-aware.
But the *URL builders* ignored the flags entirely, so any path that reached them
with a mismatched reciter issued a request guaranteed to 404 and surfaced only
the generic "check your internet" message.

* `recitationUrlForSurah` / `recitationUrlForVerse` now return `String?` — `null`
  when the reciter cannot serve that layout.
* `playSurah` / `playVerse` detect the `null` and show a specific Arabic message
  naming the reciter and the layout.
* `selectReciter` validated **after** writing to `quranReciterProvider`, so a
  rejected pick was still persisted and then broke the *other* layout on the next
  use. Validation now happens first, and an invalid choice is not persisted.
* `SurahScreen`'s reciter menu hard-coded `forSurah()` even mid-Ayah playback;
  it is now mode-aware like the player bar's.

### P-8 · Medium · The empty pre-dawn countdown

The obvious "next prayer = first prayer later than now" loop finds nothing after
Isha, because all five prayers have passed. The controller therefore computes
**tomorrow's** Fajr in that window, so the countdown is meaningful from Isha
until dawn instead of showing `00:00:00` for hours.

### P-9 · Medium · Stale Qibla geometry

`_bootstrap()` reset `_stage`, `_streamError` and `_hasReading`, but **not** the
position-derived fields. Since `_qiblaBearing` is *preferred over* the plugin's
own offset in `_onQiblahReading`, a retry (or a resume from Settings) whose GPS
fix timed out would keep rendering the bearing and declination of the **previous**
fix — a needle pointing at the Kaaba as seen from the old location, with no
error shown. All five fields are now cleared at the start of the bootstrap.

### P-10 · Medium · A crash above the Arctic Circle

This was found *by the new tests*, not by reading. `adhan`'s solar maths returns
`NaN` inside the polar circles, where no twilight exists, and it throws from
`TimeComponents.fromDouble`. A user in Tromsø (69.6° N) opening the prayer-times
tab would have hit an unhandled exception. `_recompute()` now wraps the call and
shows an Arabic explanation with the suggestion to try another convention.
`test/prayer_times_test.dart` pins both halves: `adhan` **does** throw at 69.6° N
(so the guard is justified), and 64.1° N (Reykjavík, just inside the circle) must
still work in both solstices (so the guard is not over-broad).

### P-12 · Low · Misleading error text

`_fail(error)` unconditionally produced
`'تعذّر تشغيل التلاوة. تأكد من اتصالك بالإنترنت…'` — telling a user to check their
internet when the real cause was an unsupported reciter edition. It now accepts an
optional complete `message`, and the technical detail is only appended when there
is one.

---

## 3. Also verified as correct

Audited and **not** bugs — recorded so the next pass does not re-open them:


---

## 4. Things worth knowing (not defects)

* **`flutter analyze` is clean, but it did not catch the main bugs.** Every issue
  in §2 except P-10 was invisible to the analyzer — mock data, an O(n²) loop and
  a stale-state path are all type-correct. Static analysis was necessary, not
  sufficient; the new tests exist because of this.
* **`adhan.Coordinates` has no `const` constructor**, and `PrayerTimes` has no
  2-argument overload — both were compile errors I hit and fixed (the factory is
  `(coordinates, DateComponents, parameters)`).
* **`Notifier`'s `ref` has no `mounted` getter** (only `StatefulWidget`'s `State`
  does), hence the explicit `_disposed` flag.
* **`adhan` returns device-local times.** Absolute wall-clock assertions in tests
  are therefore timezone-dependent; the tests assert *ordering* and *intervals*,
  which are environment-independent.
* **Presets legitimately differ by 1 minute on Dhuhr** — most methods add a +1
  minute safety offset, Umm al-Qura (an Isha-interval method) adds none. The test
  allows that band instead of demanding exact equality.
* **`pubspec.yaml` line 2 shows mojibake** (`ØµÙ„Ø§Ø©`) and starts with a UTF-8
  BOM. The BOM is what makes `flutter analyze` emit the `char-code` lint
  (`Au caractère Ligne:1:34`). `pub` tolerates both, so this is cosmetic — but it
  is the only analyzer complaint on the whole project.

---

## 5. Deliberately not done

| Item | Why |
|------|-----|
| Remove the 5 unused dependencies (`flutter_svg`, `shared_preferences`, `intl`, `flutter_local_notifications`, `timezone`) | Intentional scaffolding: `flutter_local_notifications` + `timezone` are the natural next step for adhan alerts, and dropping `timezone` would require re-checking `coreLibraryDesugaring`. Not my call to delete. |
| Strip the BOM / fix the mojibake description in `pubspec.yaml` | Cosmetic; `pub` accepts it, and editing a partly IDE-maintained file risks churn for no runtime gain. |

---

## 6. Verification

| Step | Check | Result |
|------|-------|--------|
| 1 | `flutter analyze lib test` | **No issues found** (3.0 s) |
| 2 | `flutter test` | **41/41 passed** (6 s) |
| 3 | Global Ayah numbering | All **6 236** Ayahs verified contiguous, 1 → 6236 |
| 4 | Cairo timetable ordering | fajr < sunrise < dhuhr < asr < maghrib < isha ✔ |
| 5 | Cairo day length (Jun) | sunrise → maghrib ≈ 14 h ✔ |
| 6 | All 5 presets | 6 non-null times each; Dhuhr within 1 min across presets |
| 7 | Presets differ on Fajr | ISNA later than Egyptian (15° vs 19.5°) ✔ |
| 8 | 4 latitudes (Sydney, Reykjavík, Cairo, Nairobi) | All well-ordered |
| 9 | Polar circle | `adhan` throws at 69.6° N → **guard required and present** |
| 10 | CDN URL shapes | `…/audio-surah/128/ar.alafasy/114.mp3`, `…/audio/128/ar.alafasy/8.mp3` |
| 11 | Reciter capability | Unsupported layout → `null`, never a 404 URL |
| 12 | Pre-existing Qibla suite | 23/23 still passing |

### Test suite

```
test/qibla_math_test.dart      23 tests  (pre-existing, unchanged)
test/quran_data_test.dart       7 tests  (new)
test/prayer_times_test.dart    11 tests  (new)
                              ─────────
                              41 tests, all passing
```

**`test/quran_data_test.dart`** — the exhaustive 6 236-Ayah walk, memoisation
stability, out-of-range clamping, the verse cache (both `withVerseEndSymbol`
variants must not collide), Surah metadata, and the recitation-URL builders.

**`test/prayer_times_test.dart`** — `AppPrayer` (sunrise excluded from
current/next), `PrayerTimesState` sentinel-`copyWith` semantics, and the `adhan`
maths: ordering, day length, all five presets, the high-latitude rule, and the
polar circle in both directions.

Run everything with `flutter test`.

---

## 7. Files changed

| File | Change |
|------|--------|
| `lib/features/prayer_times/presentation/controllers/prayer_times_controller.dart` | **New** (≈330 lines): `CalculationPreset`, `AppPrayer`, `PrayerSlot`, `PrayerTimesState`, `PrayerTimesNotifier` + provider |
| `lib/features/prayer_times/presentation/screens/prayer_times_screen.dart` | Rewritten: real timetable, live countdown, preset selector, permission/fallback banners, 24 h times |
| `lib/features/quran/data/quran_data.dart` | `globalAyahNumber` → O(1) prefix-sum table with a 6 236 sanity guard + clamping; URL builders return `String?` and honour the reciter capability flags |
| `lib/features/quran/data/quran_audio_player.dart` | Handle the `null` URL; validate the reciter *before* persisting it; `_fail` takes an optional message |
| `lib/features/quran/presentation/screens/surah_screen.dart` | Reciter menu is mode-aware |

---

## Appendix · The previous pass (2026-09-26, Qibla compass)

That pass fixed the Qibla defects, all confirmed still green by the 23
`qibla_math_test.dart` tests re-run here:

| # | Sev | Issue | Status |
|---|-----|-------|--------|
| Q-1 | Critical | `ACCESS_FINE_LOCATION` never requested at runtime → no position → no Qibla direction at all | Fixed |
| Q-2 | Critical | Alignment test used the raw, unnormalised `qiblah` (can be 400°+) → `abs() < 3` was never true | Fixed + tested |
| Q-3 | High | Magnetic azimuth used as true north → needle off by the local declination (≈ +4° Egypt, ±13° N. America) | Fixed + tested |
| Q-4 | High | No sensor calibration path | Fixed |
| Q-5 | Medium | Plugin's `atan()` + quadrant heuristics returns unnormalised values in the southern/western hemisphere | Replaced with `atan2` |
| Q-6 | Medium | Stream errors and permission failures produced one generic message, no recovery | Fixed |
| Q-7 | Medium | `IndexedStack` mounted all 5 tabs at launch → the location dialog popped up on the prayer-times tab | Fixed (TickerMode gating) |
| Q-8 | Medium | Returning from Settings re-prompted on every resume | Fixed |
| Q-9 | Medium | Magnetometer + a 60 fps animation ran while the tab was hidden | Fixed |
| Q-10 | Medium | Ayah number markers rendered *before* the text instead of between the Ayahs | Fixed |
| Q-11 | Medium | `QuranFonts.ensureLoaded()` / `configureAudioSession()` documented "call from main()" but never called | Fixed |
| Q-12 | Low | `assets/fonts/` referenced by code but missing | Fixed |
| Q-13 | Low | Stray unused `NeverScrollableScrollFitEmpty` class | Removed |
| Q-15 | Info | Prayer times was hard-coded mock data | **Fixed this pass (P-1)** |
| Q-16 | Info | `permission_handler` intentionally not added (the project's own `LocationAccess` already covers it) | Decision, unchanged |

See the original `DEBUG_REPORT.md` for that pass's full detail, including the
numeric cross-checks of the compass maths against published bearings.

| `lib/features/qibla/presentation/screens/qibla_screen.dart` | Clear the stale bearing/declination/position at the start of `_bootstrap()` |
| `test/quran_data_test.dart` | **New** — 7 tests |
| `test/prayer_times_test.dart` | **New** — 11 tests |
| `DEBUG_REPORT_2026-09-27.md` | This report |

No dependency was added or removed, no Android manifest change, and no change to
the Qibla maths that the previous pass verified.

| Schedule local notifications for each prayer | `flutter_local_notifications` is wired up and desugaring is enabled, but a full adhan-alarm feature (exact-alarm permissions, `SCHEDULE_EXACT_ALARM`, boot rescheduling, per-prayer channels) is a feature, not a debug fix. The `CalculationPreset` enum is the natural input to it. |
| Persist the Tasbeeh/Adhkar counters with `shared_preferences` | Needs a migration story and a decision on whether counts reset per day. A product decision, not a bug. |
| Empty `assets/images/` and `assets/audio/` | Harmless — Flutter accepts registered-but-empty asset directories. Remove the entries if the folders stay empty. |

* **Qibla maths** (`qibla_math_test.dart`): `atan2` bearing, true-north
  declination, normalised alignment test, `359°→0°` wrap. 23 tests, all passing.
* **`HeadingSmoother`** averages sine/cosine rather than raw degrees, so the
  needle takes the short arc across north instead of spinning 358°.
* **Lifecycle**: `QiblaScreen` cancels both subscriptions and calls
  `FlutterQiblah().dispose()` in `dispose()`; it also releases the magnetometer
  when the tab goes hidden via the `TickerMode` visibility signal, so the sensor
  and a 60 fps animation do not run in the background.
* **Permission flow**: `ACCESS_FINE_LOCATION` is requested at runtime *and*
  declared in the manifest; `sensor.compass` / `location.gps` are correctly
  `required="false"`.
* **Tasbeeh** wraps `Vibration` in `try/catch` and resets the counter at the
  target rather than letting it run past.
* **Adhkar** counters cap at `maxCount`, mark completion, and reset on tap.
* **`QuranAudioController`** guards against out-of-order loads with a
  `_loadToken`, and disposes the player and all four subscriptions in
  `ref.onDispose`.
* **No `print()`** anywhere in `lib/`; no `Timer` without a `cancel`.
* All 38 `Icons.*` names used were checked against the SDK — all exist.
