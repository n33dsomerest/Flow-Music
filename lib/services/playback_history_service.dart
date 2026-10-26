import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models/song_model.dart';
import '../data/sources/innertube_api_client.dart';

/// Service managing user playback frequency, history, and smart recommendations.
class PlaybackHistoryService {
  static final PlaybackHistoryService _instance = PlaybackHistoryService._internal();
  factory PlaybackHistoryService() => _instance;
  PlaybackHistoryService._internal();

  static const String _playCountsKey = 'user_play_counts';
  static const String _songMetadataKey = 'user_song_metadata_cache';
  static const String _recentHistoryKey = 'user_recent_play_history';

  final InnerTubeApiClient _apiClient = InnerTubeApiClient();

  /// Record a song playback, incrementing its play count and caching metadata.
  Future<void> recordPlay(SongModel song) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Update play count
      final countsRaw = prefs.getString(_playCountsKey);
      final Map<String, int> counts = countsRaw != null
          ? (jsonDecode(countsRaw) as Map).map((k, v) => MapEntry(k.toString(), (v as num).toInt()))
          : {};

      counts[song.id] = (counts[song.id] ?? 0) + 1;
      await prefs.setString(_playCountsKey, jsonEncode(counts));

      // 2. Cache song metadata
      final metaRaw = prefs.getString(_songMetadataKey);
      final Map<String, dynamic> metadata = metaRaw != null
          ? Map<String, dynamic>.from(jsonDecode(metaRaw) as Map)
          : {};

      metadata[song.id] = song.toJson();
      await prefs.setString(_songMetadataKey, jsonEncode(metadata));

      // 3. Add to recent history (up to 50 items)
      final historyList = prefs.getStringList(_recentHistoryKey) ?? [];
      historyList.remove(song.id);
      historyList.insert(0, song.id);
      if (historyList.length > 50) {
        historyList.removeRange(50, historyList.length);
      }
      await prefs.setStringList(_recentHistoryKey, historyList);

      debugPrint('[PlaybackHistory] Recorded play for "${song.title}" (count: ${counts[song.id]})');
    } catch (e) {
      debugPrint('[PlaybackHistory] Error recording play: $e');
    }
  }

  /// Get most frequently played songs (sorted descending by play count).
  Future<List<MapEntry<SongModel, int>>> getMostPlayedSongs({int limit = 12}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final countsRaw = prefs.getString(_playCountsKey);
      final metaRaw = prefs.getString(_songMetadataKey);

      if (countsRaw == null || metaRaw == null) return [];

      final counts = (jsonDecode(countsRaw) as Map).map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
      final metadata = Map<String, dynamic>.from(jsonDecode(metaRaw) as Map);

      final sortedEntries = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      final results = <MapEntry<SongModel, int>>[];
      for (final entry in sortedEntries.take(limit)) {
        final songJson = metadata[entry.key];
        if (songJson != null) {
          try {
            final song = SongModel.fromJson(songJson as Map<String, dynamic>);
            results.add(MapEntry(song, entry.value));
          } catch (_) {}
        }
      }

      return results;
    } catch (e) {
      debugPrint('[PlaybackHistory] Error getting most played: $e');
      return [];
    }
  }

  /// Get songs the user might like ("เพลงที่คุณอาจจะชอบ") based on top artists and listening tastes.
  Future<List<SongModel>> getRecommendedSongs({int limit = 15}) async {
    try {
      final mostPlayed = await getMostPlayedSongs(limit: 6);
      final playedSongTitles = mostPlayed.map((e) => e.key.title.toLowerCase().trim()).toSet();

      // If user has listening history, recommend based on top artists
      if (mostPlayed.isNotEmpty) {
        final artistCounts = <String, int>{};
        for (final entry in mostPlayed) {
          final artist = entry.key.artist.split(',')[0].trim();
          if (artist.isNotEmpty && artist != 'Unknown Artist') {
            artistCounts[artist] = (artistCounts[artist] ?? 0) + entry.value;
          }
        }

        final sortedArtists = artistCounts.keys.toList()
          ..sort((a, b) => artistCounts[b]!.compareTo(artistCounts[a]!));

        if (sortedArtists.isNotEmpty) {
          final topArtist = sortedArtists.first;
          debugPrint('[PlaybackHistory] Generating recommendations for top artist: $topArtist');
          final artistSongs = await _apiClient.search(topArtist);

          // Filter out already heavily played songs so the user discovers new music they might like
          final recommendations = artistSongs
              .where((s) => !playedSongTitles.contains(s.title.toLowerCase().trim()))
              .toList();

          if (recommendations.isNotEmpty) {
            return recommendations.take(limit).toList();
          }
        }
      }

      // Default recommendations: trending Thai songs
      final defaults = await _apiClient.search('เพลงรักฮิตโดนใจ');
      return defaults.take(limit).toList();
    } catch (e) {
      debugPrint('[PlaybackHistory] Error getting recommendations: $e');
      return [];
    }
  }
}
