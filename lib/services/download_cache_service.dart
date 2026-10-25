import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models/song_model.dart';
import '../data/sources/innertube_api_client.dart';

/// Service managing offline song downloads and local storage.
class DownloadCacheService {
  static const String _downloadedKey = 'downloaded_songs_cache';
  final InnerTubeApiClient _apiClient = InnerTubeApiClient();

  /// Get list of all downloaded offline songs.
  Future<List<SongModel>> getDownloadedSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_downloadedKey) ?? [];
    return jsonList
        .map((item) => SongModel.fromJson(jsonDecode(item) as Map<String, dynamic>))
        .toList();
  }

  /// Check if a song is downloaded locally.
  Future<bool> isSongDownloaded(String songId) async {
    final songs = await getDownloadedSongs();
    return songs.any((s) => s.id == songId);
  }

  /// Download a song for offline playback.
  Future<bool> downloadSong(SongModel song) async {
    try {
      final streamInfo = await _apiClient.getStreamInfo(song.id);
      if (streamInfo == null || streamInfo.streamUrl.isEmpty) {
        return false;
      }

      final dir = await getApplicationDocumentsDirectory();
      final audioDir = Directory('${dir.path}/downloads');
      if (!await audioDir.exists()) {
        await audioDir.create(recursive: true);
      }

      final ext = streamInfo.format.isM4a ? 'm4a' : 'webm';
      final filePath = '${audioDir.path}/${song.id}.$ext';
      final file = File(filePath);

      // Download audio binary stream
      final response = await http.get(
        Uri.parse(streamInfo.streamUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://music.youtube.com/',
        },
      );

      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);

        // Save metadata
        final downloadedSong = song.copyWith(
          isDownloaded: true,
          streamUrl: filePath,
          addedAt: DateTime.now(),
        );

        final prefs = await SharedPreferences.getInstance();
        final currentList = prefs.getStringList(_downloadedKey) ?? [];
        currentList.removeWhere((item) {
          final s = jsonDecode(item) as Map<String, dynamic>;
          return s['id'] == song.id;
        });
        currentList.add(jsonEncode(downloadedSong.toJson()));
        await prefs.setStringList(_downloadedKey, currentList);

        return true;
      }
    } catch (e) {
      debugPrint('[DownloadCacheService] Error downloading song: $e');
    }
    return false;
  }

  /// Remove a song from offline storage.
  Future<void> removeDownloadedSong(String songId) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final audioDir = Directory('${dir.path}/downloads');
      final m4aFile = File('${audioDir.path}/$songId.m4a');
      final webmFile = File('${audioDir.path}/$songId.webm');

      if (await m4aFile.exists()) await m4aFile.delete();
      if (await webmFile.exists()) await webmFile.delete();

      final prefs = await SharedPreferences.getInstance();
      final currentList = prefs.getStringList(_downloadedKey) ?? [];
      currentList.removeWhere((item) {
        final s = jsonDecode(item) as Map<String, dynamic>;
        return s['id'] == songId;
      });
      await prefs.setStringList(_downloadedKey, currentList);
    } catch (e) {
      debugPrint('[DownloadCacheService] Error removing song: $e');
    }
  }
}
