import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/constants/app_colors.dart';
import '../controllers/tasbeeh_controller.dart';

class TasbeehScreen extends ConsumerWidget {
  const TasbeehScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasbeeh = ref.watch(tasbeehProvider);
    final notifier = ref.read(tasbeehProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progress =
        tasbeeh.target > 0 ? (tasbeeh.counter / tasbeeh.target) : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('المسبحة الإلكترونية'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => notifier.reset(),
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => notifier.increment(),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 16),
              _buildDhikrChips(tasbeeh, notifier, isDark),
              const Spacer(),
              _buildCounter(tasbeeh, progress, isDark),
              const Spacer(),
              _buildFooter(tasbeeh, notifier, isDark),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDhikrChips(TasbeehState s, TasbeehNotifier n, bool isDark) {
    final items = [
      "سُبْحَانَ اللَّهِ",
      "الْحَمْدُ لِلَّهِ",
      "اللَّهُ أَكْبَرُ",
      "أَسْتَغْفِرُ اللَّهَ"
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: items.map((d) {
          final sel = s.currentDhikr == d;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text(d,
                  style: GoogleFonts.cairo(
                      fontSize: 12,
                      color: sel
                          ? Colors.white
                          : (isDark ? Colors.white : AppColors.textDark))),
              selected: sel,
              selectedColor: AppColors.primaryEmerald,
              onSelected: (_) => n.setDhikr(d),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCounter(TasbeehState s, double p, bool isDark) {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 250,
            height: 250,
            child: CircularProgressIndicator(
              value: p,
              strokeWidth: 12,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.secondaryGold),
              backgroundColor: isDark ? Colors.white10 : Colors.black12,
            ),
          ),
          Container(
            width: 210,
            height: 210,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark ? AppColors.cardSurfaceDark : Colors.white,
              boxShadow: [
                BoxShadow(
                    color: AppColors.primaryEmerald.withValues(alpha: 0.12),
                    blurRadius: 16)
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(s.currentDhikr,
                    style: GoogleFonts.amiri(
                        fontSize: 20,
                        color: AppColors.secondaryGold,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text('${s.counter}',
                    style: GoogleFonts.cairo(
                        fontSize: 50,
                        fontWeight: FontWeight.bold,
                        color:
                            isDark ? Colors.white : AppColors.primaryEmerald)),
                Text('الهدف: ${s.target}',
                    style: GoogleFonts.cairo(
                        fontSize: 13, color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(TasbeehState s, TasbeehNotifier n, bool isDark) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('الإجمالي: ${s.totalCount}',
                  style: GoogleFonts.cairo(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.secondaryGold)),
              DropdownButton<int>(
                value: s.target,
                dropdownColor:
                    isDark ? AppColors.cardSurfaceDark : Colors.white,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 33, child: Text("33")),
                  DropdownMenuItem(value: 99, child: Text("99")),
                  DropdownMenuItem(value: 100, child: Text("100")),
                ],
                onChanged: (v) => v != null ? n.setTarget(v) : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text('انقر في أي مكان للتسبيح',
            style: GoogleFonts.cairo(fontSize: 12, color: AppColors.textMuted)),
      ],
    );
  }
}
