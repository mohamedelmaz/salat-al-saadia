import 'package:flutter/foundation.dart';

import 'quran_data.dart';

/// Lifecycle of the recitation player.
enum QuranPlaybackStatus {
  /// Nothing loaded.
  idle,

  /// `setUrl` is running (network fetch of the mp3 metadata).
  loading,

  /// Playback started but the decoder is starved — the "loading" spinner case.
  buffering,
  playing,
  paused,
  completed,
  error,
}

/// Immutable snapshot of the recitation player, rendered by `QuranAudioBar`.
@immutable
class QuranAudioState {
  const QuranAudioState({
    this.status = QuranPlaybackStatus.idle,
    this.surahNumber,
    this.verseNumber,
    this.isVersePlayback = false,
    this.reciter = QuranReciter.alafasy,
    this.position = Duration.zero,
    this.duration,
    this.speed = 1.0,
    this.repeatCurrent = false,
    this.errorMessage,
  });

  final QuranPlaybackStatus status;
  final int? surahNumber;

  /// Set only in Ayah-by-Ayah mode.
  final int? verseNumber;
  final bool isVersePlayback;
  final QuranReciter reciter;
  final Duration position;
  final Duration? duration;
  final double speed;

  /// Repeats the current Ayah/Surah (ideal for memorisation).
  final bool repeatCurrent;

  /// Arabic, user-facing error text; cleared by [QuranAudioController.acknowledgeError].
  final String? errorMessage;

  bool get hasTrack => surahNumber != null;
  bool get isPlaying => status == QuranPlaybackStatus.playing;
  bool get isBusy =>
      status == QuranPlaybackStatus.loading ||
      status == QuranPlaybackStatus.buffering;
  bool get hasFailed => status == QuranPlaybackStatus.error;

  QuranAudioState copyWith({
    QuranPlaybackStatus? status,
    int? surahNumber,
    int? verseNumber,
    bool? isVersePlayback,
    QuranReciter? reciter,
    Duration? position,
    Duration? duration,
    double? speed,
    bool? repeatCurrent,
    String? errorMessage,
    bool clearError = false,
    bool clearDuration = false,
  }) {
    return QuranAudioState(
      status: status ?? this.status,
      surahNumber: surahNumber ?? this.surahNumber,
      verseNumber: verseNumber ?? this.verseNumber,
      isVersePlayback: isVersePlayback ?? this.isVersePlayback,
      reciter: reciter ?? this.reciter,
      position: position ?? this.position,
      duration: clearDuration ? null : (duration ?? this.duration),
      speed: speed ?? this.speed,
      repeatCurrent: repeatCurrent ?? this.repeatCurrent,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
