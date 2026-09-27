import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import 'quran_audio_state.dart';
import 'quran_data.dart';

export 'quran_audio_state.dart';

/// Plays the Quran recitation.
///
/// Uses `just_audio` (Apache-2.0/MIT, ExoPlayer/media3 on Android) against the
/// free Islamic Network CDN. Compared with the previous no-op play button this
/// implementation:
///
///  * reports the real buffering state, so the button can show a spinner,
///  * surfaces failures through [QuranAudioState.errorMessage] (shown as a
///    SnackBar) instead of silently doing nothing,
///  * supports both "whole Surah" and "single Ayah" playback, auto-advancing to
///    the next Ayah so listening can continue uninterrupted,
///  * repeats the current Ayah on demand for memorisation,
///  * survives navigation because the player lives in a Riverpod notifier above
///    the widget tree.
class QuranAudioController extends Notifier<QuranAudioState> {
  final AudioPlayer _player = AudioPlayer();

  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<PlayerException>? _errorSubscription;

  /// Guards against late results from a previous track overwriting newer state.
  int _loadToken = 0;

  @override
  QuranAudioState build() {
    _playerStateSubscription = _player.playerStateStream.listen(_onPlayerState);
    _positionSubscription = _player.positionStream.listen((Duration position) {
      if (!state.hasTrack) return;
      state = state.copyWith(position: position);
    });
    _durationSubscription = _player.durationStream.listen((Duration? duration) {
      state = state.copyWith(
        duration: duration,
        clearDuration: duration == null,
      );
    });
    _errorSubscription = _player.errorStream.listen(_fail);

    ref.onDispose(() {
      _loadToken++;
      _playerStateSubscription?.cancel();
      _positionSubscription?.cancel();
      _durationSubscription?.cancel();
      _errorSubscription?.cancel();
      _player.dispose();
    });

    return const QuranAudioState();
  }

  /// Configures the platform audio session for spoken-word playback.
  ///
  /// Call it from `main()`: it makes the recitation duck/pause correctly when a
  /// phone call or another media app starts.
  static Future<void> configureAudioSession() async {
    final AudioSession session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
  }

  /// Plays a whole Surah.
  Future<void> playSurah(int surahNumber) async {
    final QuranRepository repository = ref.read(quranRepositoryProvider);
    final QuranReciter reciter = ref.read(quranReciterProvider);
    final String? url = repository.recitationUrlForSurah(surahNumber, reciter);
    if (url == null) {
      _unsupportedEdition(reciter, isVersePlayback: false);
      return;
    }
    await _load(
      url: url,
      surahNumber: surahNumber,
      isVersePlayback: false,
      reciter: reciter,
    );
  }

  /// Plays a single Ayah.
  Future<void> playVerse(int surahNumber, int verseNumber) async {
    final QuranRepository repository = ref.read(quranRepositoryProvider);
    final QuranReciter reciter = ref.read(quranReciterProvider);
    final String? url =
        repository.recitationUrlForVerse(surahNumber, verseNumber, reciter);
    if (url == null) {
      _unsupportedEdition(reciter, isVersePlayback: true);
      return;
    }
    await _load(
      url: url,
      surahNumber: surahNumber,
      verseNumber: verseNumber,
      isVersePlayback: true,
      reciter: reciter,
    );
  }

  /// The selected reciter has no edition in the layout the user is playing.
  /// Fall back to a reciter that does, so the button is never a silent no-op.
  void _unsupportedEdition(
    QuranReciter reciter, {
    required bool isVersePlayback,
  }) {
    final List<QuranReciter> supported = isVersePlayback
        ? QuranReciter.forVerse()
        : QuranReciter.forSurah();
    final QuranReciter fallback = supported.first;

    // The provider is left untouched: it already holds `reciter`, and
    // persisting anything else here would silently change the user's choice
    // for the layout that *does* work.
    _fail(
      null,
      message: 'القارئ «${reciter.arabicName}» غير متاح '
          '${isVersePlayback ? 'لآية مفردة' : 'للسورة كاملة'} على هذا الخادم، '
          'تم التحويل إلى «${fallback.arabicName}».',
    );
    state = state.copyWith(reciter: fallback);
  }

  /// Remembers the chosen reciter and reloads the current track with it.
  ///
  /// The requested reciter is validated against the *current* playback mode
  /// first: the CDN does not publish every edition in both layouts, and the
  /// menus are mode-aware, so a mismatch here means the state changed
  /// underneath us. In that case the choice is not persisted (it would break
  /// the other layout later) and the current track keeps playing.
  Future<void> selectReciter(QuranReciter reciter) async {
    final bool isVerse = state.isVersePlayback;
    final bool supported = isVerse ? reciter.verseAudio : reciter.surahAudio;
    if (!supported) {
      _fail(
        null,
        message: 'القارئ «${reciter.arabicName}» غير متاح '
            '${isVerse ? 'لآية مفردة' : 'للسورة كاملة'} على هذا الخادم.',
      );
      return;
    }

    // The provider is only written once the reciter is known to be usable, so
    // the stored preference always matches the layout being played.
    ref.read(quranReciterProvider.notifier).state = reciter;

    final int? surahNumber = state.surahNumber;
    if (surahNumber == null || reciter == state.reciter) return;

    if (isVerse && state.verseNumber != null) {
      await playVerse(surahNumber, state.verseNumber!);
    } else {
      await playSurah(surahNumber);
    }
  }

  /// Play/pause toggle used by the player bar.
  Future<void> togglePlayPause() async {
    if (!state.hasTrack) return;

    if (_player.playing) {
      await _player.pause();
      return;
    }

    if (state.status == QuranPlaybackStatus.completed) {
      await _player.seek(Duration.zero);
    }
    final AudioSession session = await AudioSession.instance;
    await session.setActive(true);
    unawaited(_player.play());
  }

  /// Stops playback and frees the decoder.
  Future<void> stop() async {
    _loadToken++;
    await _player.stop();
    final AudioSession session = await AudioSession.instance;
    await session.setActive(false);
    state = const QuranAudioState();
  }

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
    state = state.copyWith(speed: speed);
  }

  /// Toggles "repeat this Ayah/Surah" (LoopMode.one).
  Future<void> toggleRepeat() async {
    final bool repeat = !state.repeatCurrent;
    state = state.copyWith(repeatCurrent: repeat);
    await _player.setLoopMode(repeat ? LoopMode.one : LoopMode.off);
  }

  /// Clears [QuranAudioState.errorMessage] once it has been shown.
  void acknowledgeError() {
    if (state.errorMessage == null) return;
    state = state.copyWith(clearError: true);
  }

  /// Next Ayah in Ayah mode, next Surah in Surah mode.
  Future<void> skipNext() async {
    final int? surahNumber = state.surahNumber;
    if (surahNumber == null) return;
    final QuranRepository repository = ref.read(quranRepositoryProvider);

    if (state.isVersePlayback) {
      final int nextVerse = (state.verseNumber ?? 1) + 1;
      if (nextVerse <= repository.verseCountOf(surahNumber)) {
        await playVerse(surahNumber, nextVerse);
      } else if (surahNumber < repository.totalSurahCount) {
        await playSurah(surahNumber + 1);
      }
      return;
    }

    if (surahNumber < repository.totalSurahCount) {
      await playSurah(surahNumber + 1);
    }
  }

  /// Previous Ayah in Ayah mode, previous Surah in Surah mode.
  Future<void> skipPrevious() async {
    final int? surahNumber = state.surahNumber;
    if (surahNumber == null) return;
    final QuranRepository repository = ref.read(quranRepositoryProvider);

    if (state.isVersePlayback) {
      final int previousVerse = (state.verseNumber ?? 1) - 1;
      if (previousVerse >= 1) {
        await playVerse(surahNumber, previousVerse);
      } else if (surahNumber > 1) {
        final int previousSurah = surahNumber - 1;
        await playVerse(previousSurah, repository.verseCountOf(previousSurah));
      }
      return;
    }

    if (surahNumber > 1) {
      await playSurah(surahNumber - 1);
    }
  }

  Future<void> _load({
    required String url,
    required int surahNumber,
    required bool isVersePlayback,
    required QuranReciter reciter,
    int? verseNumber,
  }) async {
    final int token = ++_loadToken;
    state = QuranAudioState(
      status: QuranPlaybackStatus.loading,
      surahNumber: surahNumber,
      verseNumber: verseNumber,
      isVersePlayback: isVersePlayback,
      reciter: reciter,
      speed: state.speed,
      repeatCurrent: state.repeatCurrent,
    );

    try {
      await _player.setUrl(url);
      if (token != _loadToken) return;

      await _player
          .setLoopMode(state.repeatCurrent ? LoopMode.one : LoopMode.off);
      await _player.setSpeed(state.speed);

      final AudioSession session = await AudioSession.instance;
      await session.setActive(true);
      if (token != _loadToken) return;

      // `play()` completes only when playback ends, so it is not awaited.
      unawaited(_player.play());
    } catch (error) {
      if (token != _loadToken) return;
      _fail(error);
    }
  }

  void _onPlayerState(PlayerState playerState) {
    final ProcessingState processing = playerState.processingState;
    final QuranPlaybackStatus next = switch (processing) {
      ProcessingState.idle => QuranPlaybackStatus.idle,
      ProcessingState.loading => QuranPlaybackStatus.loading,
      ProcessingState.buffering => QuranPlaybackStatus.buffering,
      ProcessingState.ready => playerState.playing
          ? QuranPlaybackStatus.playing
          : QuranPlaybackStatus.paused,
      ProcessingState.completed => QuranPlaybackStatus.completed,
    };

    state = state.copyWith(status: next);

    if (processing == ProcessingState.completed) {
      unawaited(_handleCompletion());
    }
  }

  /// Auto-advances to the next Ayah unless the current one is on repeat.
  Future<void> _handleCompletion() async {
    final QuranAudioState current = state;
    if (current.repeatCurrent && _player.loopMode == LoopMode.one) {
      return; // just_audio restarts the same track by itself.
    }

    if (current.isVersePlayback &&
        current.surahNumber != null &&
        current.verseNumber != null) {
      final int nextVerse = current.verseNumber! + 1;
      final int verseCount =
          ref.read(quranRepositoryProvider).verseCountOf(current.surahNumber!);
      if (nextVerse <= verseCount) {
        await playVerse(current.surahNumber!, nextVerse);
        return;
      }
    }

    state = current.copyWith(
      status: QuranPlaybackStatus.completed,
      position: current.duration ?? current.position,
    );
  }

  /// Moves the player into the error state and records a user-facing [message].
  ///
  /// [technicalDetail] is appended for debugging; pass `null` when the message
  /// is already complete and self-explanatory.
  void _fail(Object? technicalDetail, {String? message}) {
    final String detail = switch (technicalDetail) {
      null => '',
      final PlayerException e => e.message ?? 'player error #${e.code}',
      final Object e => e.toString(),
    };

    state = state.copyWith(
      status: QuranPlaybackStatus.error,
      errorMessage: message ??
          'تعذّر تشغيل التلاوة. تأكد من اتصالك بالإنترنت ثم أعد المحاولة.'
              '${detail.isEmpty ? '' : '\n($detail)'}',
    );

    if (kDebugMode && detail.isNotEmpty) {
      debugPrint('QuranAudioController: playback failed -> $detail');
    }
  }
}

final NotifierProvider<QuranAudioController, QuranAudioState>
    quranAudioProvider =
    NotifierProvider<QuranAudioController, QuranAudioState>(
  QuranAudioController.new,
);
