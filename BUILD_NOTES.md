# Build notes — صلاة-السعدية (salat_al_saadia)

Environment this project builds on (verified working):

- Flutter 3.47.2 (stable) · Dart 3.13.2 · DevTools 2.60.0
- Android SDK platforms 33–37 installed, build-tools 36.0.0, JDK 17 (`Android Studio\jbr`)
- AGP 9 / Gradle 9 / Kotlin built-in — very strict about old plugin build files

## Build commands

```bash
# Debug APK (runs in JIT mode, all ABIs)
flutter build apk --debug

# Release APK — ARM only (see "Blocked gen_snapshot" below)
flutter build apk --release --target-platform android-arm,android-arm64
```

Output:

| Build   | File | Size |
|---------|------|------|
| Debug   | `build/app/outputs/flutter-apk/app-debug.apk`   | ~160 MB (all ABIs, unminified) |
| Release | `build/app/outputs/flutter-apk/app-release.apk` | ~31 MB (ARM only, AOT, R8) |

## Environment-specific fixes that are already in place

1. **Two Qibla plugins ship build files that break AGP 9 / Gradle 9.**
   `flutter_qiblah` and `flutter_compass_v2` are therefore redirected to locally patched copies
   that live next to the project (`../flutter_qiblah_local`, `../flutter_compass_v2_local`) via
   `dependency_overrides` in `pubspec.yaml`. The patched copies only differ in their Android
   build files: no private `buildscript`/classpath, no `jcenter`, `compileSdk 36`, modern
   `lint {}` / `kotlin { compilerOptions { … } }` blocks, no `package` in the manifest.
   *If the project is moved or the copies are deleted, restore them or re-apply the patch.*

2. **Windows Developer Mode is unavailable (no admin rights).** Flutter only needs plugin
   symlinks for the desktop platform folders, and this is an Android-only app, so
   `windows/` and `linux/` were renamed to `windows_disabled/` / `linux_disabled/`
   (reversible — rename them back if desktop support is ever needed).

3. **`flutter_local_notifications` requires core library desugaring.**
   `android/app/build.gradle.kts` enables `isCoreLibraryDesugaringEnabled` and adds
   `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")`.

4. **Blocked `gen_snapshot.exe` (release builds only).** Windows application-control policy
   blocks two of Flutter's AOT tools on this machine:

   | Tool | Status |
   |------|--------|
   | `…/android-x64-release/windows-x64/gen_snapshot.exe` | blocked (error `Une stratégie de contrôle d'application a bloqué ce fichier`) |
   | `…/android-arm-profile/windows-x64/gen_snapshot.exe` | blocked |
   | `android-arm-release`, `android-arm64-release`, `android-arm64-profile`, `android-x64-profile` | work fine |

   Because the x86_64 release tool is blocked, a plain `flutter build apk --release`
   (which builds arm + arm64 + x86_64) fails. Restricting the ABI list to ARM works and
   covers every real Android phone:
   `flutter build apk --release --target-platform android-arm,android-arm64`.
   Debug builds are unaffected (they are JIT and never invoke `gen_snapshot`).
   Lifting this needs admin rights (Developer Mode / Application Control policy).

5. **Launcher icons** were generated with `flutter_launcher_icons` from
   `assets/icons/app_icon.png` (+ adaptive foreground
   `assets/icons/app_icon_foreground.png`, background `#0F5132`) into
   `android/app/src/main/res/mipmap-*` and `drawable-*`; the manifest uses
   `android:icon="@mipmap/launcher_icon"`.

## Known build failures already resolved

6. **A `compileSdk 34` override in `android/build.gradle.kts` broke the whole build.**
   The file ended with:

   ```kotlin
   // FIX: Force all plugins to use compileSdk 34
   subprojects {
       afterEvaluate {
           if (hasProperty("android")) {
               android { compileSdk = 34 }
           }
       }
   }
   ```

   That is **Groovy DSL pasted into a Kotlin DSL file**. `hasProperty(...)` and the
   `android { }` accessor are not available on a Kotlin `Project`, so the build
   script failed to *compile* — before any task ran:

   ```
   e: android/build.gradle.kts:30:13: Unresolved reference 'android'.
   e: android/build.gradle.kts:31:17: Unresolved reference 'compileSdk'.
   2 errors
   ```

   **Symptom to recognise:** a 2–3 second "BUILD FAILED" that never mentions a
   task, a plugin or a source file — only `build.gradle.kts` line numbers. That
   is a *script compilation* error, not a build error, and `flutter clean` will
   never fix it.

   The block was **deleted**, not corrected, because it was never needed *and*
   actively harmful:
   * the app already uses `compileSdk = flutter.compileSdkVersion` (= **36** on
     this toolchain), and both locally patched plugins already declare
     `compileSdk 36` in their own build files (see item 1);
   * forcing **34** would have failed *again*, less obviously: androidx AAR
     metadata published for `compileSdk` 35+ refuses to link against a 34
     `compileSdk`.

   **If a plugin ever does need a different `compileSdk`, change it in that
   plugin's own build file** — that is exactly what the local patched copies are
   for. Do not add a global `subprojects { afterEvaluate { … } }` override to
   `android/build.gradle.kts`.

   Verified after removal: `flutter build apk --release --target-platform
   android-arm,android-arm64` → **`app-release.apk`, 38.66 MB**.

## Known limitations

- **Release signing uses the Android debug keystore** (`android/app/build.gradle.kts`
  still has the template `signingConfig = signingConfigs.getByName("debug")`). The APK is
  installable everywhere for testing but cannot be uploaded to Google Play as-is.
  For a store build, create a keystore and a `key.properties`, then replace that line.
- Debug APKs include three ABIs and are unminified, hence ~160 MB. For small debug
  builds use `flutter build apk --debug --target-platform android-arm64`.
- `flutter analyze` is clean; the only remaining build output is a Flutter warning that
  `flutter_compass_v2` / `flutter_qiblah` still apply the Kotlin Gradle Plugin — harmless
  today, but those plugins should be migrated to built-in Kotlin eventually.
