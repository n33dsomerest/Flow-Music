import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import '../data/models/song_model.dart';
import '../data/sources/innertube_api_client.dart';
import 'download_cache_service.dart';
import 'playback_history_service.dart';

enum PlaybackStatus { idle, loading, playing, paused, completed, error }

/// Background-capable Audio Player Service managing queue, streaming, and playback states.
class AudioPlayerService {
  static final AudioPlayerService _instance = AudioPlayerService._internal();
  factory AudioPlayerService() => _instance;
  AudioPlayerService._internal();

  final AudioPlayer _player = AudioPlayer();
  final InnerTubeApiClient _apiClient = InnerTubeApiClient();

  // Queue state
  final List<SongModel> _queue = [];
  int _currentIndex = -1;
  bool _isRadioEnabled = true;

  // Stream controllers
  final _songController = StreamController<SongModel?>.broadcast();
  final _statusController = StreamController<PlaybackStatus>.broadcast();
  final _queueController = StreamController<List<SongModel>>.broadcast();

  // Public streams
  Stream<SongModel?> get currentSongStream => _songController.stream;
  Stream<PlaybackStatus> get statusStream => _statusController.stream;
  Stream<List<SongModel>> get queueStream => _queueController.stream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<Duration> get bufferedPositionStream => _player.bufferedPositionStream;

  SongModel? get currentSong => _currentIndex >= 0 && _currentIndex < _queue.length ? _queue[_currentIndex] : null;
  bool get isPlaying => _player.playing;
  List<SongModel> get queue => List.unmodifiable(_queue);

  Future<void> init() async {
    // Configure OS Audio Session for background playback and headphone disconnect handling
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    // Listen to player state changes
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.loading ||
          state.processingState == ProcessingState.buffering) {
        _statusController.add(PlaybackStatus.loading);
      } else if (state.processingState == ProcessingState.completed) {
        _statusController.add(PlaybackStatus.completed);
        skipToNext(); // Auto play next track
      } else if (state.playing) {
        _statusController.add(PlaybackStatus.playing);
      } else {
        _statusController.add(PlaybackStatus.paused);
      }
    });

    _player.playbackEventStream.listen(
      (event) {},
      onError: (Object e, StackTrace st) {
        debugPrint('[AudioPlayerService] Playback event error: $e');
        _statusController.add(PlaybackStatus.error);
      },
    );
  }

  /// Play a song immediately, replacing or prepending the queue.
  Future<void> playSong(SongModel song) async {
    _queue.clear();
    _queue.add(song);
    _currentIndex = 0;
    _queueController.add(_queue);
    await _loadAndPlayCurrent();
  }

  /// Add a song to play next or end of queue.
  void addToQueue(SongModel song) {
    _queue.add(song);
    _queueController.add(_queue);
    if (_currentIndex == -1) {
      _currentIndex = 0;
      _loadAndPlayCurrent();
    }
  }

  /// Play an entire list of songs.
  Future<void> playPlaylist(List<SongModel> songs, {int initialIndex = 0}) async {
    if (songs.isEmpty) return;
    _queue.clear();
    _queue.addAll(songs);
    _currentIndex = initialIndex.clamp(0, _queue.length - 1);
    _queueController.add(_queue);
    await _loadAndPlayCurrent();
  }

  /// Skip to next song in queue or fetch radio suggestions.
  Future<void> skipToNext() async {
    if (_currentIndex + 1 < _queue.length) {
      _currentIndex++;
      await _loadAndPlayCurrent();
    } else if (_isRadioEnabled && currentSong != null) {
      // Auto fetch endless radio when queue finishes
      _statusController.add(PlaybackStatus.loading);
      final suggestions = await _apiClient.getRadioQueue(currentSong!.id);
      if (suggestions.isNotEmpty) {
        _queue.addAll(suggestions);
        _queueController.add(_queue);
        _currentIndex++;
        await _loadAndPlayCurrent();
      }
    }
  }

  /// Skip to previous song.
  Future<void> skipToPrevious() async {
    if (_player.position.inSeconds > 3) {
      // If played more than 3 seconds, restart current track
      await _player.seek(Duration.zero);
    } else if (_currentIndex > 0) {
      _currentIndex--;
      await _loadAndPlayCurrent();
    }
  }

  Future<void> play() async {
    if (_player.audioSource == null && _currentIndex >= 0 && _currentIndex < _queue.length) {
      await _loadAndPlayCurrent();
    } else {
      await _player.play();
    }
  }

  Future<void> pause() async => await _player.pause();
  Future<void> seek(Duration position) async => await _player.seek(position);

  /// Load stream URL via REA InnerTube client and play.
  Future<void> _loadAndPlayCurrent() async {
    final song = currentSong;
    if (song == null) return;

    _songController.add(song);
    _statusController.add(PlaybackStatus.loading);

    // Record play count and playback history
    PlaybackHistoryService().recordPlay(song);

    try {
      // 1. Check if song has a valid local file path (offline mode)
      if (song.isDownloaded && song.streamUrl != null && song.streamUrl!.isNotEmpty) {
        final file = File(song.streamUrl!);
        if (await file.exists()) {
          debugPrint('[AudioPlayerService] Playing local file: ${song.streamUrl}');
          await _player.stop();
          await _player.setFilePath(song.streamUrl!);
          _player.play();
          return;
        }
      }

      // Check DownloadCacheService if it was downloaded previously
      final isDownloaded = await DownloadCacheService().isSongDownloaded(song.id);
      if (isDownloaded) {
        final list = await DownloadCacheService().getDownloadedSongs();
        final match = list.firstWhere((s) => s.id == song.id, orElse: () => song);
        if (match.streamUrl != null && await File(match.streamUrl!).exists()) {
          debugPrint('[AudioPlayerService] Playing cached file: ${match.streamUrl}');
          await _player.stop();
          await _player.setFilePath(match.streamUrl!);
          _player.play();
          return;
        }
      }

      bool isPlaying = false;

      // (a) getStreamInfo -> setUrl (ครอบ try/catch แยก, ล้มเหลวให้ clearCache)
      try {
        final streamInfo = await _apiClient.getStreamInfo(song.id);
        if (streamInfo != null && streamInfo.streamUrl.isNotEmpty) {
          debugPrint('[AudioPlayerService] Setting stream URL (${streamInfo.format.mimeType})');
          await _player.stop();
          Map<String, String>? headers;
          if (streamInfo.userAgent != null && streamInfo.userAgent!.isNotEmpty) {
            headers = {'User-Agent': streamInfo.userAgent!};
          }
          await _player.setUrl(
            streamInfo.streamUrl,
            headers: headers,
          );
          _player.play();
          isPlaying = true;
        } else {
          InnerTubeApiClient.clearCache(song.id);
        }
      } catch (e) {
        debugPrint('[AudioPlayerService] Stream URL playback failed: $e');
        InnerTubeApiClient.clearCache(song.id);
      }

      // (b) ถ้ายังไม่เล่น เรียก _apiClient.downloadAudioToTemp(song.id) แล้ว setFilePath เล่นจากไฟล์
      if (!isPlaying) {
        try {
          debugPrint('[AudioPlayerService] Attempting temp audio file download fallback...');
          final tempPath = await _apiClient.downloadAudioToTemp(song.id);
          if (tempPath != null && await File(tempPath).exists()) {
            debugPrint('[AudioPlayerService] Playing from temp audio file: $tempPath');
            await _player.stop();
            await _player.setFilePath(tempPath);
            _player.play();
            isPlaying = true;
          }
        } catch (e) {
          debugPrint('[AudioPlayerService] Temp file playback failed: $e');
        }
      }

      // (c) ถ้ายังไม่เล่นอีก ให้ส่ง PlaybackStatus.error
      if (!isPlaying) {
        debugPrint('[AudioPlayerService] All playback attempts failed for ${song.id}');
        _statusController.add(PlaybackStatus.error);
      }
    } catch (e) {
      debugPrint('[AudioPlayerService] Playback error: $e');
      InnerTubeApiClient.clearCache(song.id);
      _statusController.add(PlaybackStatus.error);
    }
  }

  void dispose() {
    _player.dispose();
    _songController.close();
    _statusController.close();
    _queueController.close();
  }
}
