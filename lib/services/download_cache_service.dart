import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models/song_model.dart';
import '../data/sources/innertube_api_client.dart';

/// Service managing offline song downloads and local storage at /storage/emulated/0/Music.
class DownloadCacheService {
  static const String _downloadedKey = 'downloaded_songs_cache';
  final InnerTubeApiClient _apiClient = InnerTubeApiClient();

  /// Resolve download directory: prefers shared device Music folder (/storage/emulated/0/Music)
  Future<Directory> _getDownloadDirectory() async {
    try {
      final sharedMusicDir = Directory('/storage/emulated/0/Music');
      if (await sharedMusicDir.exists()) {
        return sharedMusicDir;
      }
      return await sharedMusicDir.create(recursive: true);
    } catch (e) {
      debugPrint('[DownloadCacheService] Failed to access /storage/emulated/0/Music ($e), using app storage');
      final appDir = await getApplicationDocumentsDirectory();
      final fallbackDir = Directory('${appDir.path}/Music');
      if (!await fallbackDir.exists()) {
        await fallbackDir.create(recursive: true);
      }
      return fallbackDir;
    }
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

  /// Download a song for offline playback to /storage/emulated/0/Music.
  Future<bool> downloadSong(SongModel song) async {
    try {
      final streamInfo = await _apiClient.getStreamInfo(song.id);
      if (streamInfo == null || streamInfo.streamUrl.isEmpty) {
        debugPrint('[DownloadCacheService] Could not resolve stream for ${song.id}');
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

      debugPrint('[DownloadCacheService] Downloading to $filePath');

      final client = http.Client();
      final request = http.Request('GET', Uri.parse(streamInfo.streamUrl));
      if (streamInfo.streamUrl.contains('googlevideo.com')) {
        request.headers['User-Agent'] = 'com.google.android.youtube/19.29.35 (Linux; U; Android 11)';
      }

      final streamedResponse = await client.send(request).timeout(const Duration(seconds: 45));
      if (streamedResponse.statusCode == 200) {
        final sink = file.openWrite();
        await streamedResponse.stream.pipe(sink);
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

        debugPrint('[DownloadCacheService] Download complete: $filePath');
        return true;
      } else {
        debugPrint('[DownloadCacheService] Stream request failed with code ${streamedResponse.statusCode}');
      }
    } catch (e) {
      debugPrint('[DownloadCacheService] Error downloading song: $e');
    }
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
