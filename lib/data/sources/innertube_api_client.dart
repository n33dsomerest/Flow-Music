import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../core/constants/api_constants.dart';
import '../../core/crypto/cipher_resolver.dart';
import '../models/song_model.dart';
import '../models/stream_info_model.dart';

/// Client-Side Direct InnerTube API Client.
/// Communicates directly with YouTube Music endpoints without intermediary servers.
class InnerTubeApiClient {
  final http.Client _httpClient;
  final CipherResolver _cipherResolver;

  InnerTubeApiClient({
    http.Client? httpClient,
    CipherResolver? cipherResolver,
  })  : _httpClient = httpClient ?? http.Client(),
        _cipherResolver = cipherResolver ?? CipherResolver();

  /// Search for songs, albums, and playlists on YouTube Music.
  Future<List<SongModel>> search(String query, {String? filter}) async {
    final url = Uri.parse(ApiConstants.searchEndpoint);
    final payload = ApiConstants.defaultClientContext();
    payload['query'] = query;
    if (filter != null) {
      payload['params'] = filter; // e.g. 'EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D' for Songs
    }

    try {
      final response = await _httpClient.post(
        url,
        headers: ApiConstants.defaultHeaders,
        body: jsonEncode(payload),
      );

      if (response.statusCode != 200) {
        debugPrint('[InnerTube] Search failed with status: ${response.statusCode}');
        return [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return _parseSearchSongs(data);
    } catch (e) {
      debugPrint('[InnerTube] Search error: $e');
      return [];
    }
  }

  /// Get direct audio stream URL and format details for a specific video/song.
  Future<StreamInfo?> getStreamInfo(String videoId) async {
    final url = Uri.parse(ApiConstants.playerEndpoint);
    final payload = ApiConstants.defaultClientContext();
    payload['videoId'] = videoId;
    payload['playbackContext'] = {
      'contentPlaybackContext': {
        'html5Preference': 'HTML5_PREF_WANTS',
        'signatureTimestamp': 19900,
      }
    };

    try {
      final response = await _httpClient.post(
        url,
        headers: ApiConstants.defaultHeaders,
        body: jsonEncode(payload),
      );

      if (response.statusCode != 200) {
        debugPrint('[InnerTube] Player failed with status: ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final streamingData = data['streamingData'] as Map<String, dynamic>?;
      if (streamingData == null) return null;

      final adaptiveFormats = (streamingData['adaptiveFormats'] as List<dynamic>?) ?? [];
      final audioFormats = <AudioFormat>[];

      for (final fmt in adaptiveFormats) {
        final formatMap = fmt as Map<String, dynamic>;
        final mimeType = formatMap['mimeType'] as String? ?? '';
        if (mimeType.startsWith('audio/')) {
          audioFormats.add(AudioFormat.fromJson(formatMap));
        }
      }

      if (audioFormats.isEmpty) return null;

      // Select optimal audio format:
      // Priority 1: Opus itag 251 (highest quality ~160kbps)
      // Priority 2: M4A itag 140 (~128kbps)
      // Priority 3: Highest bitrate available
      audioFormats.sort((a, b) {
        if (a.itag == 251) return -1;
        if (b.itag == 251) return 1;
        if (a.itag == 140) return -1;
        if (b.itag == 140) return 1;
        return b.bitrate.compareTo(a.bitrate);
      });

      final selectedFormat = audioFormats.first;
      final rawUrl = selectedFormat.url ?? '';
      final signatureCipher = selectedFormat.signatureCipher;

      // Deobfuscate cipher and throttling via REA Cipher Engine
      final resolvedUrl = await _cipherResolver.resolveStreamUrl(
        rawUrl: rawUrl,
        signatureCipher: signatureCipher,
      );

      final expiresInSeconds = int.tryParse(streamingData['expiresInSeconds']?.toString() ?? '21600') ?? 21600;
      final expiresAt = DateTime.now().add(Duration(seconds: expiresInSeconds));

      return StreamInfo(
        videoId: videoId,
        streamUrl: resolvedUrl,
        format: selectedFormat,
        expiresAt: expiresAt,
      );
    } catch (e) {
      debugPrint('[InnerTube] getStreamInfo error: $e');
      return null;
    }
  }

  /// Get "Up Next" / Endless Radio queue based on the currently playing song.
  Future<List<SongModel>> getRadioQueue(String videoId) async {
    final url = Uri.parse(ApiConstants.nextEndpoint);
    final payload = ApiConstants.defaultClientContext();
    payload['videoId'] = videoId;
    payload['isAudioOnly'] = true;

    try {
      final response = await _httpClient.post(
        url,
        headers: ApiConstants.defaultHeaders,
        body: jsonEncode(payload),
      );

      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tabRenderer = data['contents']?['singleColumnMusicWatchNextResultsRenderer']
          ?['tabRenderer'] as Map<String, dynamic>?;

      final queueRenderer = tabRenderer?['content']?['musicQueueRenderer']
          ?['content']?['playlistPanelRenderer'] as Map<String, dynamic>?;

      final contents = (queueRenderer?['contents'] as List<dynamic>?) ?? [];
      final List<SongModel> songs = [];

      for (final item in contents) {
        final renderer = item['playlistPanelVideoRenderer'] as Map<String, dynamic>?;
        if (renderer != null) {
          final id = renderer['videoId'] as String? ?? '';
          final title = renderer['title']?['runs']?[0]?['text'] as String? ?? 'Unknown Title';
          final artist = renderer['longBylineText']?['runs']?[0]?['text'] as String? ?? 'Unknown Artist';
          String? album;
          final bylineRuns = renderer['longBylineText']?['runs'] as List<dynamic>?;
          if (bylineRuns != null && bylineRuns.length > 2) {
            album = bylineRuns[2]['text'] as String?;
          }
          final durationStr = renderer['lengthText']?['runs']?[0]?['text'] as String? ?? '0:00';
          final thumbnails = renderer['thumbnail']?['thumbnails'] as List<dynamic>?;
          final thumbUrl = (thumbnails != null && thumbnails.isNotEmpty)
              ? thumbnails.last['url'] as String? ?? ''
              : '';

          if (id.isNotEmpty && id != videoId) {
            songs.add(SongModel(
              id: id,
              title: title,
              artist: artist,
              album: album,
              durationSeconds: _parseDurationStringToSeconds(durationStr),
              thumbnailUrl: thumbUrl,
            ));
          }
        }
      }

      return songs;
    } catch (e) {
      debugPrint('[InnerTube] getRadioQueue error: $e');
      return [];
    }
  }

  /// Get songs from a public YouTube / YouTube Music playlist by playlistId.
  Future<List<SongModel>> getPlaylistSongs(String playlistId) async {
    final cleanId = playlistId.startsWith('VL') ? playlistId : 'VL$playlistId';
    final url = Uri.parse(ApiConstants.browseEndpoint);
    final payload = ApiConstants.defaultClientContext();
    payload['browseId'] = cleanId;

    try {
      final response = await _httpClient.post(
        url,
        headers: ApiConstants.defaultHeaders,
        body: jsonEncode(payload),
      );

      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final sectionList = data['contents']?['singleColumnBrowseResultsRenderer']
          ?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']
          ?['contents'] as List<dynamic>?;

      if (sectionList == null) return [];

      final List<SongModel> songs = [];
      for (final section in sectionList) {
        final shelf = section['musicPlaylistShelfRenderer'] as Map<String, dynamic>?;
        if (shelf == null) continue;

        final items = (shelf['contents'] as List<dynamic>?) ?? [];
        for (final item in items) {
          final renderer = item['musicResponsiveListItemRenderer'] as Map<String, dynamic>?;
          if (renderer == null) continue;

          final flexColumns = renderer['flexColumns'] as List<dynamic>?;
          if (flexColumns == null || flexColumns.isEmpty) continue;

          // Title
          final titleRun = flexColumns[0]['musicResponsiveListItemFlexColumnRenderer']
              ?['text']?['runs']?[0];
          final title = titleRun?['text'] as String? ?? '';

          // Artist
          String artist = 'Unknown Artist';
          String? album;
          if (flexColumns.length > 1) {
            final runs = flexColumns[1]['musicResponsiveListItemFlexColumnRenderer']
                ?['text']?['runs'] as List<dynamic>?;
            if (runs != null && runs.isNotEmpty) {
              artist = runs[0]['text'] as String? ?? 'Unknown Artist';
              if (runs.length > 2) {
                album = runs[2]['text'] as String?;
              }
            }
          }

          final videoId = renderer['playlistItemData']?['videoId'] as String? ??
              titleRun?['navigationEndpoint']?['watchEndpoint']?['videoId'] as String? ??
              '';

          final thumbnails = renderer['thumbnail']?['musicThumbnailRenderer']
              ?['thumbnail']?['thumbnails'] as List<dynamic>?;
          final thumbUrl = (thumbnails != null && thumbnails.isNotEmpty)
              ? thumbnails.last['url'] as String? ?? ''
              : '';

          if (videoId.isNotEmpty && title.isNotEmpty) {
            songs.add(SongModel(
              id: videoId,
              title: title,
              artist: artist,
              album: album,
              durationSeconds: 0,
              thumbnailUrl: thumbUrl,
            ));
          }
        }
      }

      return songs;
    } catch (e) {
      debugPrint('[InnerTube] getPlaylistSongs error: $e');
      return [];
    }
  }

  /// Parse song items from search endpoint JSON payload.
  List<SongModel> _parseSearchSongs(Map<String, dynamic> data) {
    final List<SongModel> results = [];
    try {
      final sectionList = data['contents']?['tabbedSearchResultsRenderer']
          ?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']
          ?['contents'] as List<dynamic>?;

      if (sectionList == null) return [];

      for (final section in sectionList) {
        final shelf = section['musicShelfRenderer'] as Map<String, dynamic>?;
        if (shelf == null) continue;

        final items = (shelf['contents'] as List<dynamic>?) ?? [];
        for (final item in items) {
          final renderer = item['musicResponsiveListItemRenderer'] as Map<String, dynamic>?;
          if (renderer == null) continue;

          final flexColumns = renderer['flexColumns'] as List<dynamic>?;
          if (flexColumns == null || flexColumns.isEmpty) continue;

          // Title
          final titleRun = flexColumns[0]['musicResponsiveListItemFlexColumnRenderer']
              ?['text']?['runs']?[0];
          final title = titleRun?['text'] as String? ?? '';

          // Artist & Album
          String artist = 'Unknown Artist';
          String? album;
          if (flexColumns.length > 1) {
            final runs = flexColumns[1]['musicResponsiveListItemFlexColumnRenderer']
                ?['text']?['runs'] as List<dynamic>?;
            if (runs != null && runs.isNotEmpty) {
              artist = runs[0]['text'] as String? ?? 'Unknown Artist';
              if (runs.length > 2) {
                album = runs[2]['text'] as String?;
              }
            }
          }

          // Video ID
          final videoId = renderer['playlistItemData']?['videoId'] as String? ??
              titleRun?['navigationEndpoint']?['watchEndpoint']?['videoId'] as String? ??
              '';

          // Thumbnail
          final thumbnails = renderer['thumbnail']?['musicThumbnailRenderer']
              ?['thumbnail']?['thumbnails'] as List<dynamic>?;
          final thumbUrl = (thumbnails != null && thumbnails.isNotEmpty)
              ? thumbnails.last['url'] as String? ?? ''
              : '';

          if (videoId.isNotEmpty && title.isNotEmpty) {
            results.add(SongModel(
              id: videoId,
              title: title,
              artist: artist,
              album: album,
              durationSeconds: 0,
              thumbnailUrl: thumbUrl,
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('[InnerTube] Parse search error: $e');
    }
    return results;
  }

  int _parseDurationStringToSeconds(String duration) {
    final parts = duration.split(':');
    if (parts.length == 2) {
      final mins = int.tryParse(parts[0]) ?? 0;
      final secs = int.tryParse(parts[1]) ?? 0;
      return (mins * 60) + secs;
    } else if (parts.length == 3) {
      final hrs = int.tryParse(parts[0]) ?? 0;
      final mins = int.tryParse(parts[1]) ?? 0;
      final secs = int.tryParse(parts[2]) ?? 0;
      return (hrs * 3600) + (mins * 60) + secs;
    }
    return 0;
  }
}
