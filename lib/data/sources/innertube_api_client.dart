import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../core/constants/api_constants.dart';
import '../../core/crypto/cipher_resolver.dart';
import '../models/song_model.dart';
import '../models/stream_info_model.dart';

/// Client-Side Direct InnerTube API Client.
/// Communicates directly with YouTube Music endpoints using dynamic InnerTube API key and recursive JSON parser.
class InnerTubeApiClient {
  final http.Client _httpClient;
  final CipherResolver _cipherResolver;

  String? _apiKey;
  String? _visitorData;
  DateTime? _configFetchedAt;

  InnerTubeApiClient({
    http.Client? httpClient,
    CipherResolver? cipherResolver,
  })  : _httpClient = httpClient ?? http.Client(),
        _cipherResolver = cipherResolver ?? CipherResolver();

  /// Dynamically fetch latest INNERTUBE_API_KEY and VISITOR_DATA from YouTube Music.
  Future<String> _ensureApiKey() async {
    if (_apiKey != null &&
        _configFetchedAt != null &&
        DateTime.now().difference(_configFetchedAt!).inHours < 12) {
      return _apiKey!;
    }

    try {
      final response = await _httpClient.get(
        Uri.parse(ApiConstants.youtubeMusicBaseUrl),
        headers: ApiConstants.defaultHeaders,
      );

      final keyMatch = RegExp(r'"INNERTUBE_API_KEY":\s*"([^"]+)"').firstMatch(response.body);
      if (keyMatch != null) {
        _apiKey = keyMatch.group(1);
      }

      final visitorMatch = RegExp(r'"VISITOR_DATA":\s*"([^"]+)"').firstMatch(response.body);
      if (visitorMatch != null) {
        _visitorData = visitorMatch.group(1);
      }

      _configFetchedAt = DateTime.now();
    } catch (e) {
      debugPrint('[InnerTube] Failed to fetch dynamic API key: $e');
    }

    // Fallback public key if scraping fails
    _apiKey ??= 'AIzaSyAO_FJ2SlqU8Q4VhANkdifigqxbAbBNDWo';
    return _apiKey!;
  }

  /// Helper to send authenticated POST request to InnerTube endpoint.
  Future<http.Response> _postInnerTube(String endpoint, Map<String, dynamic> payload) async {
    final apiKey = await _ensureApiKey();
    final url = Uri.parse('$endpoint?key=$apiKey&prettyPrint=false');

    final headers = Map<String, String>.from(ApiConstants.defaultHeaders);
    headers['X-Goog-Api-Key'] = apiKey;
    if (_visitorData != null) {
      headers['X-Goog-Visitor-Id'] = _visitorData!;
    }

    return await _httpClient.post(
      url,
      headers: headers,
      body: jsonEncode(payload),
    );
  }

  /// Search for songs, albums, and playlists on YouTube Music.
  Future<List<SongModel>> search(String query, {String? filter}) async {
    final payload = ApiConstants.defaultClientContext();
    payload['query'] = query;
    if (filter != null) {
      payload['params'] = filter;
    }

    try {
      final response = await _postInnerTube(ApiConstants.searchEndpoint, payload);

      if (response.statusCode != 200) {
        debugPrint('[InnerTube] Search failed with status: ${response.statusCode}');
        return [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return _extractSongsFromTree(data);
    } catch (e) {
      debugPrint('[InnerTube] Search error: $e');
      return [];
    }
  }

  /// Get direct audio stream URL and format details for a specific video/song.
  Future<StreamInfo?> getStreamInfo(String videoId) async {
    final payload = ApiConstants.defaultClientContext();
    payload['videoId'] = videoId;
    payload['playbackContext'] = {
      'contentPlaybackContext': {
        'html5Preference': 'HTML5_PREF_WANTS',
        'signatureTimestamp': 19900,
      }
    };

    try {
      final response = await _postInnerTube(ApiConstants.playerEndpoint, payload);

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

      // Prefer Opus ~160kbps (itag 251) or M4A (itag 140)
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
    final payload = ApiConstants.defaultClientContext();
    payload['videoId'] = videoId;
    payload['isAudioOnly'] = true;

    try {
      final response = await _postInnerTube(ApiConstants.nextEndpoint, payload);
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final songs = _extractSongsFromTree(data);
      return songs.where((s) => s.id != videoId).toList();
    } catch (e) {
      debugPrint('[InnerTube] getRadioQueue error: $e');
      return [];
    }
  }

  /// Get songs from a public YouTube / YouTube Music playlist by playlistId.
  Future<List<SongModel>> getPlaylistSongs(String playlistId) async {
    final cleanId = playlistId.startsWith('VL') ? playlistId : 'VL$playlistId';
    final payload = ApiConstants.defaultClientContext();
    payload['browseId'] = cleanId;

    try {
      final response = await _postInnerTube(ApiConstants.browseEndpoint, payload);
      if (response.statusCode != 200) {
        debugPrint('[InnerTube] getPlaylistSongs failed status: ${response.statusCode}');
        return [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return _extractSongsFromTree(data);
    } catch (e) {
      debugPrint('[InnerTube] getPlaylistSongs error: $e');
      return [];
    }
  }

  /// Robust recursive JSON parser: traverses any response tree to locate all songs.
  List<SongModel> _extractSongsFromTree(Map<String, dynamic> root) {
    final List<SongModel> results = [];
    final Set<String> seenIds = {};

    void traverse(dynamic node) {
      if (node is Map<String, dynamic>) {
        if (node.containsKey('musicResponsiveListItemRenderer')) {
          final song = _parseResponsiveListItem(node['musicResponsiveListItemRenderer'] as Map<String, dynamic>);
          if (song != null && !seenIds.contains(song.id)) {
            seenIds.add(song.id);
            results.add(song);
          }
          return;
        }

        if (node.containsKey('playlistPanelVideoRenderer')) {
          final song = _parsePanelVideo(node['playlistPanelVideoRenderer'] as Map<String, dynamic>);
          if (song != null && !seenIds.contains(song.id)) {
            seenIds.add(song.id);
            results.add(song);
          }
          return;
        }

        for (final value in node.values) {
          traverse(value);
        }
      } else if (node is List) {
        for (final item in node) {
          traverse(item);
        }
      }
    }

    traverse(root);
    return results;
  }

  SongModel? _parseResponsiveListItem(Map<String, dynamic> renderer) {
    try {
      final flexColumns = renderer['flexColumns'] as List<dynamic>?;
      if (flexColumns == null || flexColumns.isEmpty) return null;

      final titleRun = flexColumns[0]['musicResponsiveListItemFlexColumnRenderer']
          ?['text']?['runs']?[0];
      final title = titleRun?['text'] as String? ?? '';

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
        return SongModel(
          id: videoId,
          title: title,
          artist: artist,
          album: album,
          durationSeconds: 0,
          thumbnailUrl: thumbUrl,
        );
      }
    } catch (_) {}
    return null;
  }

  SongModel? _parsePanelVideo(Map<String, dynamic> renderer) {
    try {
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

      if (id.isNotEmpty && title.isNotEmpty) {
        return SongModel(
          id: id,
          title: title,
          artist: artist,
          album: album,
          durationSeconds: _parseDurationStringToSeconds(durationStr),
          thumbnailUrl: thumbUrl,
        );
      }
    } catch (_) {}
    return null;
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
