import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/fonts/quran_fonts.dart';
import 'core/theme/app_theme.dart';
import 'features/home/presentation/main_navigation_screen.dart';
import 'features/quran/data/quran_audio_player.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Register the bundled Quranic typeface (if one was dropped into
  // `assets/fonts/`). Both helpers document that they must run before the first
  // frame; they were never called, so the app always fell back to Google Fonts
  // and the recitation never got a spoken-word audio session.
  await QuranFonts.ensureLoaded();
  try {
    await QuranAudioController.configureAudioSession();
  } catch (_) {
    // Audio-session configuration is an enhancement: never block start-up.
  }

  runApp(
    const ProviderScope(
      child: SalatAlSaadiaApp(),
    ),
  );
}

class SalatAlSaadiaApp extends StatelessWidget {
  const SalatAlSaadiaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'صلاة-السعدية',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      locale: const Locale('ar'),
      supportedLocales: const [
        Locale('ar'),
        Locale('en'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const MainNavigationScreen(),
    );
  }
}
