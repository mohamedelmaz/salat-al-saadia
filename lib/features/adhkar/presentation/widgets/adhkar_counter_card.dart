import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vibration/vibration.dart';
import '../../../../core/constants/app_colors.dart';

class AdhkarCounterCard extends StatefulWidget {
  final String text;
  final String? virtue;
  final int maxCount;
  final VoidCallback? onCompleted;

  const AdhkarCounterCard({
    super.key,
    required this.text,
    this.virtue,
    required this.maxCount,
    this.onCompleted,
  });

  @override
  State<AdhkarCounterCard> createState() => _AdhkarCounterCardState();
}

class _AdhkarCounterCardState extends State<AdhkarCounterCard> {
  int _currentCount = 0;

  void _increment() {
    if (_currentCount < widget.maxCount) {
      setState(() => _currentCount++);
      try {
        Vibration.vibrate(duration: 30);
      } catch (_) {}

      if (_currentCount == widget.maxCount) {
        try {
          Vibration.vibrate(pattern: [0, 60, 40, 80]);
        } catch (_) {}
        widget.onCompleted?.call();
      }
    }
  }

  void _reset() {
    setState(() => _currentCount = 0);
  }

  @override
  Widget build(BuildContext context) {
    final isDone = _currentCount >= widget.maxCount;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progress =
        widget.maxCount > 0 ? (_currentCount / widget.maxCount) : 0.0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isDone
              ? (isDark ? const Color(0xFF162E20) : const Color(0xFFEDF7ED))
              : (isDark ? AppColors.cardSurfaceDark : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDone ? AppColors.secondaryGold : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _increment,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.text,
                    style: GoogleFonts.amiri(
                      fontSize: 19,
                      height: 1.8,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : AppColors.textDark,
                    ),
                    textAlign: TextAlign.justify,
                  ),
                  if (widget.virtue != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      widget.virtue!,
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        color: AppColors.secondaryGold,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDone
                              ? AppColors.secondaryGold
                              : AppColors.primaryEmerald,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '$_currentCount / ${widget.maxCount}',
                          style: GoogleFonts.cairo(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 6,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isDone
                                  ? AppColors.secondaryGold
                                  : AppColors.primaryEmerald,
                            ),
                            backgroundColor:
                                isDark ? Colors.white10 : Colors.black12,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        color: AppColors.textMuted,
                        onPressed: _reset,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
