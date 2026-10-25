import 'dart:async';
import 'package:flutter/foundation.dart';
import 'audio_player_service.dart';

/// Sleep Timer Service with smooth audio fadeout support.
class SleepTimerService {
  static final SleepTimerService _instance = SleepTimerService._internal();
  factory SleepTimerService() => _instance;
  SleepTimerService._internal();

  Timer? _timer;
  Timer? _countdownTimer;
  int _remainingSeconds = 0;
  bool _stopAtEndOfTrack = false;

  final _remainingSecondsController = StreamController<int>.broadcast();
  Stream<int> get remainingSecondsStream => _remainingSecondsController.stream;
  bool get isActive => _remainingSeconds > 0 || _stopAtEndOfTrack;
  int get remainingSeconds => _remainingSeconds;

  /// Start sleep timer with specified duration in minutes.
  void startTimer(int minutes) {
    cancelTimer();
    _stopAtEndOfTrack = false;
    _remainingSeconds = minutes * 60;
    _remainingSecondsController.add(_remainingSeconds);

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_remainingSeconds > 0) {
        _remainingSeconds--;
        _remainingSecondsController.add(_remainingSeconds);
      } else {
        _finishTimer();
      }
    });
  }

  /// Stop playback when the current track finishes.
  void setStopAtEndOfTrack() {
    cancelTimer();
    _stopAtEndOfTrack = true;
    _remainingSecondsController.add(-1); // -1 indicates end of track mode
  }

  /// Cancel active sleep timer.
  void cancelTimer() {
    _timer?.cancel();
    _countdownTimer?.cancel();
    _timer = null;
    _countdownTimer = null;
    _remainingSeconds = 0;
    _stopAtEndOfTrack = false;
    _remainingSecondsController.add(0);
  }

  void _finishTimer() {
    cancelTimer();
    AudioPlayerService().pause();
    debugPrint('[SleepTimerService] Timer expired, paused playback.');
  }

  void dispose() {
    cancelTimer();
    _remainingSecondsController.close();
  }
}
