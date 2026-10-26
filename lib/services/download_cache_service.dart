import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  /// Resolve download directory: prefers shared device Music folder (/storage/emulated/0/Music)
  Future<Directory> _getDownloadDirectory() async {
    // 1. Try public shared Music directory: /storage/emulated/0/Music
    try {
      final sharedMusicDir = Directory('/storage/emulated/0/Music');
      if (!await sharedMusicDir.exists()) {
        await sharedMusicDir.create(recursive: true);
      }
      // Test if writing is allowed
      final testFile = File('${sharedMusicDir.path}/.perm_test_${DateTime.now().millisecondsSinceEpoch}');
      await testFile.writeAsString('ok');
      await testFile.delete();
      return sharedMusicDir;
    } catch (e) {
      debugPrint('[DownloadCacheService] /storage/emulated/0/Music not writable ($e)');
    }

    // 2. Try external app storage: /storage/emulated/0/Android/data/.../files/Music
    try {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        final musicDir = Directory('${extDir.path}/Music');
        if (!await musicDir.exists()) {
          await musicDir.create(recursive: true);
        }
        return musicDir;
      }
    } catch (_) {}

    // 3. Fallback to app documents
    final appDir = await getApplicationDocumentsDirectory();
    final fallbackDir = Directory('${appDir.path}/Music');
    if (!await fallbackDir.exists()) {
      await fallbackDir.create(recursive: true);
    }
    return fallbackDir;
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

  /// Download a song for offline playback to /storage/emulated/0/Music with percentage progress.
  Future<bool> downloadSong(SongModel song, {void Function(double progress)? onProgress}) async {
    if (isDownloading(song.id)) return false;

    _activeDownloads[song.id] = 0.0;
    _downloadProgressController.add(Map.from(_activeDownloads));
    onProgress?.call(0.0);

    File? partialFile;
    try {
      final streamInfo = await _apiClient.getStreamInfo(song.id);
      if (streamInfo == null || streamInfo.streamUrl.isEmpty) {
        debugPrint('[DownloadCacheService] Could not resolve stream for ${song.id}');
        _activeDownloads.remove(song.id);
        _downloadProgressController.add(Map.from(_activeDownloads));
        return false;
      }

      final musicDir = await _getDownloadDirectory();

      // Determine extension based on mimeType
      String ext = 'm4a';
      final mime = streamInfo.format.mimeType.toLowerCase();
      if (mime.contains('audio/mp4') || mime.contains('m4a')) {
        ext = 'm4a';
      } else if (mime.contains('audio/mpeg') || mime.contains('mp3')) {
        ext = 'mp3';
      } else if (mime.contains('opus') || mime.contains('webm')) {
        ext = 'opus';
      }

      // Safe clean filename: "Artist - Title.ext"
      final safeArtist = song.artist.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
      final safeTitle = song.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
      final baseName = (safeArtist.isNotEmpty && safeTitle.isNotEmpty)
          ? '$safeArtist - $safeTitle'
          : song.id;
      final filePath = '${musicDir.path}/$baseName.$ext';
      final file = File(filePath);
      partialFile = file;

      debugPrint('[DownloadCacheService] Downloading to $filePath');

      final client = http.Client();
      final request = http.Request('GET', Uri.parse(streamInfo.streamUrl));
      if (streamInfo.userAgent != null && streamInfo.userAgent!.isNotEmpty) {
        request.headers['User-Agent'] = streamInfo.userAgent!;
      }

      final streamedResponse = await client.send(request).timeout(const Duration(seconds: 45));
      if (streamedResponse.statusCode == 200) {
        final totalBytes = streamedResponse.contentLength ?? streamInfo.format.contentLength ?? 0;
        int receivedBytes = 0;
        final sink = file.openWrite();

        await for (final chunk in streamedResponse.stream) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (totalBytes > 0) {
            final progress = (receivedBytes / totalBytes).clamp(0.0, 1.0);
            _activeDownloads[song.id] = progress;
            _downloadProgressController.add(Map.from(_activeDownloads));
            onProgress?.call(progress);
          }
        }

        await sink.flush();
        await sink.close();

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
      } else {
        debugPrint('[DownloadCacheService] Stream request failed with code ${streamedResponse.statusCode}');
      }
    } catch (e) {
      debugPrint('[DownloadCacheService] Error downloading song: $e');
      if (partialFile != null && await partialFile.exists()) {
        try {
          await partialFile.delete();
        } catch (_) {}
      }
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
