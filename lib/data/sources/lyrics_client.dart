import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../core/constants/api_constants.dart';
import '../models/lyrics_model.dart';
import '../models/song_model.dart';

/// Client for fetching synchronized and plain lyrics via LRCLIB and YouTube Music.
class LyricsClient {
  final http.Client _httpClient;

  LyricsClient({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  /// Fetch synchronized lyrics for a given song.
  Future<LyricsModel?> getLyrics(SongModel song) async {
    // 1. Try LRCLIB exact match
    final queryParams = <String, String>{
      'track_name': _cleanTitle(song.title),
      'artist_name': song.artist,
    };

    if (song.album != null && song.album!.isNotEmpty) {
      queryParams['album_name'] = song.album!;
    }
    if (song.durationSeconds > 0) {
      queryParams['duration'] = song.durationSeconds.toString();
    }

    final uri = Uri.parse(ApiConstants.lrclibGetEndpoint).replace(queryParameters: queryParams);

    try {
      final response = await _httpClient.get(
        uri,
        headers: {'User-Agent': 'FlowMusic/1.0.0 (https://github.com/flow-music)'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final syncedLyrics = data['syncedLyrics'] as String?;
        final plainLyrics = data['plainLyrics'] as String?;

        if (syncedLyrics != null && syncedLyrics.isNotEmpty) {
          return LyricsModel.fromLrc(
            title: song.title,
            artist: song.artist,
            lrcContent: syncedLyrics,
          );
        } else if (plainLyrics != null && plainLyrics.isNotEmpty) {
          return LyricsModel.plain(
            title: song.title,
            artist: song.artist,
            text: plainLyrics,
          );
        }
      } else if (response.statusCode == 404) {
        // Fallback to LRCLIB search endpoint
        return await _searchLrclib(song);
      }
    } catch (e) {
      debugPrint('[LyricsClient] Error fetching lyrics: $e');
    }

    return null;
  }

  /// Search LRCLIB if exact get query fails.
  Future<LyricsModel?> _searchLrclib(SongModel song) async {
    final searchUri = Uri.parse(ApiConstants.lrclibSearchEndpoint).replace(
      queryParameters: {'q': '${_cleanTitle(song.title)} ${song.artist}'},
    );

    try {
      final response = await _httpClient.get(
        searchUri,
        headers: {'User-Agent': 'FlowMusic/1.0.0'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> list = jsonDecode(response.body) as List<dynamic>;
        if (list.isNotEmpty) {
          final first = list.first as Map<String, dynamic>;
          final syncedLyrics = first['syncedLyrics'] as String?;
          final plainLyrics = first['plainLyrics'] as String?;

          if (syncedLyrics != null && syncedLyrics.isNotEmpty) {
            return LyricsModel.fromLrc(
              title: song.title,
              artist: song.artist,
              lrcContent: syncedLyrics,
            );
          } else if (plainLyrics != null && plainLyrics.isNotEmpty) {
            return LyricsModel.plain(
              title: song.title,
              artist: song.artist,
              text: plainLyrics,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[LyricsClient] Search error: $e');
    }
    return null;
  }

  /// Strip unwanted YouTube video suffixes like (Official Music Video), [Lyric Video], etc.
  String _cleanTitle(String title) {
    return title
        .replaceAll(RegExp(r'\s*[\(\[](?:Official|Music|Lyric|Audio|Video|HD|4K|Visualizer).*?[\)\]]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*ft\.?.*', caseSensitive: false), '')
        .trim();
  }
}
