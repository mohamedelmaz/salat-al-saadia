# صلاة-السعدية (salat_al_saadia)

تطبيق إسلامي شامل: القرآن الكريم، الأذكار، مواقيت الصلاة، التسبيح، والقبلة.

An Islamic Flutter application with five feature areas:

| Feature | Location | Main packages |
|---------|----------|---------------|
| القرآن الكريم | `lib/features/quran/` | `flutter_svg`, `google_fonts`, `audioplayers` |
| الأذكار | `lib/features/adhkar/` | `shared_preferences` |
| مواقيت الصلاة | `lib/features/prayer_times/` | `adhan`, `geolocator`, `flutter_local_notifications`, `timezone` |
| التسبيح | `lib/features/tasbeeh/` | `vibration`, `shared_preferences` |
| القبلة | `lib/features/qibla/` | `flutter_qiblah` (backed by `flutter_compass_v2`) |

Navigation is handled by a bottom-bar shell in
`lib/features/home/presentation/main_navigation_screen.dart`; state is managed with
`flutter_riverpod`. UI text is Arabic (RTL).

## Getting started

```bash
flutter pub get
flutter run                # on a connected Android device
flutter analyze            # currently clean
```

## Building APKs

```bash
flutter build apk --debug
flutter build apk --release --target-platform android-arm,android-arm64
```

Artifacts land in `build/app/outputs/flutter-apk/`.

> **Read [`BUILD_NOTES.md`](BUILD_NOTES.md) first** — this project depends on locally patched
> copies of `flutter_qiblah` / `flutter_compass_v2` (see `dependency_overrides` in
> `pubspec.yaml`), needs the desktop platform folders parked while Windows Developer Mode is
> off, and release builds must be limited to ARM ABIs because Windows application-control
> policy blocks Flutter's x86_64 AOT tool on this machine.

## App icon

Icons are generated from `assets/icons/app_icon.png` with
`dart run flutter_launcher_icons` (config in `pubspec.yaml`, background `#0F5132`).
