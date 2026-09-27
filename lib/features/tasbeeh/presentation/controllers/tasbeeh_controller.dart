import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibration/vibration.dart';

class TasbeehState {
  final int counter;
  final int target;
  final int totalCount;
  final String currentDhikr;

  TasbeehState({
    required this.counter,
    required this.target,
    required this.totalCount,
    required this.currentDhikr,
  });

  TasbeehState copyWith({
    int? counter,
    int? target,
    int? totalCount,
    String? currentDhikr,
  }) {
    return TasbeehState(
      counter: counter ?? this.counter,
      target: target ?? this.target,
      totalCount: totalCount ?? this.totalCount,
      currentDhikr: currentDhikr ?? this.currentDhikr,
    );
  }
}

class TasbeehNotifier extends StateNotifier<TasbeehState> {
  TasbeehNotifier()
      : super(TasbeehState(
          counter: 0,
          target: 33,
          totalCount: 0,
          currentDhikr: "سُبْحَانَ اللَّهِ",
        ));

  void increment() {
    int newCounter = state.counter + 1;
    int newTotal = state.totalCount + 1;

    _triggerHaptic(isCompletion: newCounter == state.target);

    if (newCounter >= state.target && state.target > 0) {
      newCounter = 0;
    }

    state = state.copyWith(counter: newCounter, totalCount: newTotal);
  }

  void reset() {
    state = state.copyWith(counter: 0);
  }

  void setTarget(int newTarget) {
    state = state.copyWith(target: newTarget, counter: 0);
  }

  void setDhikr(String dhikr) {
    state = state.copyWith(currentDhikr: dhikr, counter: 0);
  }

  Future<void> _triggerHaptic({required bool isCompletion}) async {
    try {
      if (await Vibration.hasVibrator()) {
        if (isCompletion) {
          Vibration.vibrate(pattern: [0, 80, 50, 120]);
        } else {
          Vibration.vibrate(duration: 40);
        }
      }
    } catch (_) {}
  }
}

final tasbeehProvider =
    StateNotifierProvider<TasbeehNotifier, TasbeehState>((ref) {
  return TasbeehNotifier();
});
