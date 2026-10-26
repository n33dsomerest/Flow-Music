import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide StreamInfo;
import '../data/models/song_model.dart';
import '../data/sources/innertube_api_client.dart';

/// Service managing offline song downloads with progress tracking and storage at /storage/emulated/0/Music.
class DownloadCacheService {
  static final DownloadCacheService _instance = DownloadCacheService._internal();
  factory DownloadCacheService() => _instance;
  DownloadCacheService._internal();

  static const String _downloadedKey = 'downloaded_songs_cache';
  final InnerTubeApiClient _apiClient = InnerTubeApiClient();

  // Download progress Stream: map of songId -> progress (0.0 to 1.0)
  final _downloadProgressController = StreamController<Map<String, double>>.broadcast();
  Stream<Map<String, double>> get downloadProgressStream => _downloadProgressController.stream;

  final Map<String, double> _activeDownloads = {};
  Map<String, double> get activeDownloads => Map.unmodifiable(_activeDownloads);
  double? getDownloadProgress(String songId) => _activeDownloads[songId];
  bool isDownloading(String songId) => _activeDownloads.containsKey(songId);

  /// Resolve download directory: App Documents Directory (files/Music)
  Future<Directory> _getDownloadDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final musicDir = Directory('${appDir.path}/Music');
    if (!await musicDir.exists()) {
      await musicDir.create(recursive: true);
    }
    return musicDir;
  }

  /// Get list of all downloaded offline songs that actually exist on disk.
  Future<List<SongModel>> getDownloadedSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_downloadedKey) ?? [];
    final results = <SongModel>[];

    for (final item in jsonList) {
      try {
        final song = SongModel.fromJson(jsonDecode(item) as Map<String, dynamic>);
        if (song.streamUrl != null && song.streamUrl!.isNotEmpty) {
          final file = File(song.streamUrl!);
          if (await file.exists()) {
            results.add(song);
          }
        }
      } catch (_) {}
    }
    return results;
  }

  /// Check if a song is downloaded locally and its file exists.
  Future<bool> isSongDownloaded(String songId) async {
    final songs = await getDownloadedSongs();
    return songs.any((s) => s.id == songId);
  }

  /// Download a song for offline playback with percentage progress.
  Future<bool> downloadSong(SongModel song, {void Function(double progress)? onProgress}) async {
    if (isDownloading(song.id)) return false;

    _activeDownloads[song.id] = 0.0;
    _downloadProgressController.add(Map.from(_activeDownloads));
    onProgress?.call(0.0);

    File? partialFile;
    IOSink? activeSink;
    final yt = YoutubeExplode();

    try {
      // 1. Try to fetch streamInfo (do not return false immediately if null)
      final streamInfo = await _apiClient.getStreamInfo(song.id);

      final musicDir = await _getDownloadDirectory();
      final safeArtist = song.artist.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
      final safeTitle = song.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
      final baseName = (safeArtist.isNotEmpty && safeTitle.isNotEmpty)
          ? '$safeArtist - $safeTitle'
          : song.id;

      bool downloadSuccess = false;
      String filePath = '';

      // Primary Attempt: Binary stream download via InnerTubeApiClient.getManifestResilient
      try {
        final cleanId = InnerTubeApiClient.cleanVideoId(song.id);
        final manifest = await InnerTubeApiClient.getManifestResilient(yt, cleanId);
        final List<AudioOnlyStreamInfo> audioStreams = manifest == null
            ? <AudioOnlyStreamInfo>[]
            : manifest.audioOnly.toList();

        if (audioStreams.isNotEmpty) {
          final m4aStreams = audioStreams.where((s) => s.container == StreamContainer.mp4 || s.container.name.toLowerCase() == 'mp4').toList();
          final bestAudio = m4aStreams.isNotEmpty
              ? m4aStreams.withHighestBitrate()
              : audioStreams.withHighestBitrate();

          // กำหนดนามสกุลไฟล์: audio/mp4 หรือ m4a -> m4a, webm/opus -> webm, อื่นๆ -> mp3
          String ext = 'mp3';
          final formatStr = '${bestAudio.codec} ${bestAudio.container.name}'.toLowerCase();
          if (formatStr.contains('audio/mp4') || formatStr.contains('m4a') || formatStr.contains('mp4')) {
            ext = 'm4a';
          } else if (formatStr.contains('webm') || formatStr.contains('opus')) {
            ext = 'webm';
          }

          filePath = '${musicDir.path}/$baseName.$ext';
          final file = File(filePath);
          partialFile = file;

          final stream = yt.videos.streamsClient.get(bestAudio);
          final totalBytes = bestAudio.size.totalBytes;
          int receivedBytes = 0;
          final sink = file.openWrite();
          activeSink = sink;

          await for (final chunk in stream) {
            sink.add(chunk);
            receivedBytes += chunk.length;
            final progress = totalBytes > 0
                ? (receivedBytes / totalBytes).clamp(0.0, 1.0)
                : (receivedBytes / (4 * 1024 * 1024)).clamp(0.05, 0.95);
            _activeDownloads[song.id] = progress;
            _downloadProgressController.add(Map.from(_activeDownloads));
            onProgress?.call(progress);
          }

          await sink.flush();
          await sink.close();
          activeSink = null;
          downloadSuccess = true;
          debugPrint('[DownloadCacheService] Binary download succeeded: $filePath');
        }
      } catch (e) {
        debugPrint('[DownloadCacheService] Binary download error: $e');
        if (activeSink != null) {
          try {
            await activeSink.close();
          } catch (_) {}
          activeSink = null;
        }
        if (partialFile != null && await partialFile.exists()) {
          try {
            await partialFile.delete();
          } catch (_) {}
        }
      }

      // Secondary Attempt: Direct HTTP streaming download fallback (ONLY when streamInfo != null)
      if (!downloadSuccess && streamInfo != null && streamInfo.streamUrl.isNotEmpty) {
        debugPrint('[DownloadCacheService] Trying HTTP streaming download fallback...');
        try {
          // กำหนดนามสกุลไฟล์: audio/mp4 หรือ m4a -> m4a, webm/opus -> webm, อื่นๆ -> mp3
          String ext = 'mp3';
          final mime = streamInfo.format.mimeType.toLowerCase();
          if (mime.contains('audio/mp4') || mime.contains('m4a')) {
            ext = 'm4a';
          } else if (mime.contains('webm') || mime.contains('opus')) {
            ext = 'webm';
          }

          filePath = '${musicDir.path}/$baseName.$ext';
          final file = File(filePath);
          partialFile = file;

          final client = http.Client();
          final request = http.Request('GET', Uri.parse(streamInfo.streamUrl))
            ..followRedirects = true
            ..maxRedirects = 5;

          if (streamInfo.userAgent != null && streamInfo.userAgent!.isNotEmpty) {
            request.headers['User-Agent'] = streamInfo.userAgent!;
          }

          final streamedResponse = await client.send(request).timeout(const Duration(seconds: 45));
          if (streamedResponse.statusCode >= 200 && streamedResponse.statusCode < 300) {
            final totalBytes = streamedResponse.contentLength ?? streamInfo.format.contentLength ?? 0;
            int receivedBytes = 0;
            final sink = file.openWrite();
            activeSink = sink;

            await for (final chunk in streamedResponse.stream) {
              sink.add(chunk);
              receivedBytes += chunk.length;
              final progress = totalBytes > 0
                  ? (receivedBytes / totalBytes).clamp(0.0, 1.0)
                  : (receivedBytes / (4 * 1024 * 1024)).clamp(0.05, 0.95);
              _activeDownloads[song.id] = progress;
              _downloadProgressController.add(Map.from(_activeDownloads));
              onProgress?.call(progress);
            }

            await sink.flush();
            await sink.close();
            activeSink = null;
            downloadSuccess = true;
            debugPrint('[DownloadCacheService] HTTP streaming download succeeded: $filePath');
          } else {
            debugPrint('[DownloadCacheService] Stream request failed with code ${streamedResponse.statusCode}');
          }
        } catch (e) {
          debugPrint('[DownloadCacheService] Direct HTTP download error: $e');
          if (activeSink != null) {
            try {
              await activeSink.close();
            } catch (_) {}
            activeSink = null;
          }
          if (partialFile != null && await partialFile.exists()) {
            try {
              await partialFile.delete();
            } catch (_) {}
          }
        }
      }

      if (downloadSuccess && filePath.isNotEmpty && await File(filePath).exists() && await File(filePath).length() > 1000) {
        // Save metadata
        final downloadedSong = song.copyWith(
          isDownloaded: true,
          streamUrl: filePath,
          addedAt: DateTime.now(),
        );

        final prefs = await SharedPreferences.getInstance();
        final currentList = prefs.getStringList(_downloadedKey) ?? [];
        currentList.removeWhere((item) {
          try {
            final s = jsonDecode(item) as Map<String, dynamic>;
            return s['id'] == song.id;
          } catch (_) {
            return false;
          }
        });
        currentList.add(jsonEncode(downloadedSong.toJson()));
        await prefs.setStringList(_downloadedKey, currentList);

        _activeDownloads.remove(song.id);
        _downloadProgressController.add(Map.from(_activeDownloads));
        onProgress?.call(1.0);

        debugPrint('[DownloadCacheService] Download complete: $filePath');
        return true;
      }
    } catch (e) {
      debugPrint('[DownloadCacheService] Error downloading song: $e');
      if (activeSink != null) {
        try {
          await activeSink.close();
        } catch (_) {}
        activeSink = null;
      }
      if (partialFile != null && await partialFile.exists()) {
        try {
          await partialFile.delete();
        } catch (_) {}
      }
    } finally {
      yt.close();
    }

    _activeDownloads.remove(song.id);
    _downloadProgressController.add(Map.from(_activeDownloads));
    return false;
  }

  /// Remove a song from offline storage.
  Future<void> removeDownloadedSong(String songId) async {
    try {
      final songs = await getDownloadedSongs();
      for (final song in songs) {
        if (song.id == songId) {
          if (song.streamUrl != null && song.streamUrl!.isNotEmpty) {
            final file = File(song.streamUrl!);
            if (await file.exists()) {
              await file.delete();
            }
          }
          break;
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final currentList = prefs.getStringList(_downloadedKey) ?? [];
      currentList.removeWhere((item) {
        try {
          final s = jsonDecode(item) as Map<String, dynamic>;
          return s['id'] == songId;
        } catch (_) {
          return false;
        }
      });
      await prefs.setStringList(_downloadedKey, currentList);
    } catch (e) {
      debugPrint('[DownloadCacheService] Error removing song: $e');
    }
  }
}
