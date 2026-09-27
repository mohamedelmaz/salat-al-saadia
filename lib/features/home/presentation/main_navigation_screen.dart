import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/constants/app_colors.dart';
import '../../quran/presentation/screens/quran_screen.dart';
import '../../adhkar/presentation/screens/adhkar_screen.dart';
import '../../prayer_times/presentation/screens/prayer_times_screen.dart';
import '../../tasbeeh/presentation/screens/tasbeeh_screen.dart';
import '../../qibla/presentation/screens/qibla_screen.dart';

final bottomNavIndexProvider =
    StateProvider<int>((ref) => 2); // Default to Prayer Times

class MainNavigationScreen extends ConsumerWidget {
  const MainNavigationScreen({super.key});

  final List<Widget> _screens = const [
    QuranScreen(),
    AdhkarScreen(),
    PrayerTimesScreen(),
    TasbeehScreen(),
    QiblaScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(bottomNavIndexProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: IndexedStack(
          index: currentIndex,
          // `IndexedStack` keeps every tab mounted (only the selected one is
          // painted), so each tab's `initState` runs at app start. Wrapping the
          // tabs in a `TickerMode` publishes which one is really visible:
          // animations in the hidden tabs stop (no needless 60 fps work) and
          // feature screens such as the Qibla compass use it to defer sensor or
          // permission work until the user actually opens them — otherwise the
          // location permission dialog would pop up on the prayer-times tab.
          children: <Widget>[
            for (int i = 0; i < _screens.length; i++)
              TickerMode(enabled: i == currentIndex, child: _screens[i]),
          ],
        ),
        bottomNavigationBar: NavigationBarTheme(
          data: NavigationBarThemeData(
            indicatorColor: AppColors.secondaryGold.withValues(alpha: 0.2),
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.secondaryGold,
                );
              }
              return GoogleFonts.cairo(
                fontSize: 11,
                fontWeight: FontWeight.normal,
                color: isDark ? Colors.white60 : AppColors.textMuted,
              );
            }),
          ),
          child: NavigationBar(
            selectedIndex: currentIndex,
            onDestinationSelected: (index) {
              ref.read(bottomNavIndexProvider.notifier).state = index;
            },
            backgroundColor: isDark ? AppColors.cardSurfaceDark : Colors.white,
            elevation: 0,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.menu_book_outlined),
                selectedIcon:
                    Icon(Icons.menu_book, color: AppColors.secondaryGold),
                label: 'القرآن',
              ),
              NavigationDestination(
                icon: Icon(Icons.volunteer_activism_outlined),
                selectedIcon: Icon(Icons.volunteer_activism,
                    color: AppColors.secondaryGold),
                label: 'الأذكار',
              ),
              NavigationDestination(
                icon: Icon(Icons.access_time_outlined),
                selectedIcon: Icon(Icons.access_time_filled,
                    color: AppColors.secondaryGold),
                label: 'المواقيت',
              ),
              NavigationDestination(
                icon: Icon(Icons.fingerprint),
                selectedIcon:
                    Icon(Icons.fingerprint, color: AppColors.secondaryGold),
                label: 'المسبحة',
              ),
              NavigationDestination(
                icon: Icon(Icons.explore_outlined),
                selectedIcon:
                    Icon(Icons.explore, color: AppColors.secondaryGold),
                label: 'القبلة',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
