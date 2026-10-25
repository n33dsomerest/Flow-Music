import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../core/constants/api_constants.dart';
import '../../core/crypto/cipher_resolver.dart';
import '../models/song_model.dart';
import '../models/stream_info_model.dart';

/// Client-Side Direct InnerTube API Client.
/// Communicates directly with YouTube Music endpoints using dynamic InnerTube API key,
/// multi-client fallback streaming (ANDROID_MUSIC / IOS / TVHTML5 / ANDROID_VR / Piped),
/// and recursive JSON parser.
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
  Future<http.Response> _postInnerTube(
    String endpoint,
    Map<String, dynamic> payload, {
    Map<String, String>? customHeaders,
  }) async {
    final apiKey = await _ensureApiKey();
    final url = Uri.parse('$endpoint?key=$apiKey&prettyPrint=false');

    final headers = customHeaders != null
        ? Map<String, String>.from(customHeaders)
        : Map<String, String>.from(ApiConstants.defaultHeaders);

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

  /// Get direct audio stream URL with Multi-Tier Fallback:
  /// 1. ANDROID_MUSIC (cleanest direct opus/m4a audio, unencrypted, no PO-Token needed)
  /// 2. IOS (pristine AAC 128kbps audio, direct unencrypted url)
  /// 3. TVHTML5_SIMPLY_EMBEDDED_PLAYER (unthrottled TV player)
  /// 4. ANDROID_VR (Oculus client)
  /// 5. Piped Public Proxy fallback
  /// 6. WEB_REMIX with cipher decipher
  Future<StreamInfo?> getStreamInfo(String videoId) async {
    // 1. Try ANDROID_MUSIC
    var streamInfo = await _fetchPlayerStream(
      videoId,
      clientName: 'ANDROID_MUSIC',
      clientVersion: '7.19.52',
      clientId: '21',
      userAgent: 'com.google.android.apps.youtube.music/7.19.52 (Linux; U; Android 11)',
      endpoint: ApiConstants.playerEndpoint,
    );
    if (streamInfo != null) return streamInfo;

    // 2. Try IOS client fallback
    streamInfo = await _fetchPlayerStream(
      videoId,
      clientName: 'IOS',
      clientVersion: '19.29.1',
      clientId: '5',
      userAgent: 'com.google.ios.youtube/19.29.1 (iPhone16,2; U; CPU iOS 17_5_1 like Mac OS X)',
      endpoint: 'https://www.youtube.com/youtubei/v1/player',
    );
    if (streamInfo != null) return streamInfo;

    // 3. Try TVHTML5_SIMPLY_EMBEDDED_PLAYER
    streamInfo = await _fetchPlayerStream(
      videoId,
      clientName: 'TVHTML5_SIMPLY_EMBEDDED_PLAYER',
      clientVersion: '2.0',
      clientId: '85',
      userAgent: 'Mozilla/5.0 (PlayStation; PlayStation 4/11.00) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/11.00 Safari/605.1.15',
      endpoint: 'https://www.youtube.com/youtubei/v1/player',
      referer: 'https://www.youtube.com/tv',
    );
    if (streamInfo != null) return streamInfo;

    // 4. Try ANDROID_VR
    streamInfo = await _fetchPlayerStream(
      videoId,
      clientName: 'ANDROID_VR',
      clientVersion: '1.60.19',
      clientId: '28',
      userAgent: 'Mozilla/5.0 (Linux; Android 10; Quest 2) AppleWebKit/537.36',
      endpoint: 'https://www.youtube.com/youtubei/v1/player',
    );
    if (streamInfo != null) return streamInfo;

    // 5. Try Piped API Public Mirrors
    streamInfo = await _fetchPipedStream(videoId);
    if (streamInfo != null) return streamInfo;

    // 6. Try WEB_REMIX with Cipher Resolver
    return await _fetchPlayerStream(
      videoId,
      clientName: 'WEB_REMIX',
      clientVersion: '1.20241015.01.00',
      clientId: '67',
      userAgent: ApiConstants.defaultUserAgent,
      endpoint: ApiConstants.playerEndpoint,
      referer: '${ApiConstants.youtubeMusicBaseUrl}/',
    );
  }

  Future<StreamInfo?> _fetchPlayerStream(
    String videoId, {
    required String clientName,
    required String clientVersion,
    required String clientId,
    required String userAgent,
    required String endpoint,
    String? referer,
  }) async {
    final payload = {
      'context': {
        'client': {
          'clientName': clientName,
          'clientVersion': clientVersion,
          'hl': 'en',
          'gl': 'US',
          if (clientName == 'ANDROID_MUSIC') 'androidSdkVersion': 30,
          if (clientName == 'IOS') ...{
            'deviceModel': 'iPhone16,2',
            'osName': 'iPhone',
            'osVersion': '17.5.1.21F90',
          },
          if (clientName == 'ANDROID_VR') ...{
            'deviceMake': 'Oculus',
            'deviceModel': 'Quest 2',
            'osName': 'Android',
            'osVersion': '10',
          },
        },
        if (clientName == 'TVHTML5_SIMPLY_EMBEDDED_PLAYER')
          'thirdParty': {
            'embedUrl': 'https://www.youtube.com',
          },
      },
      'videoId': videoId,
      'playbackContext': {
        'contentPlaybackContext': {
          'html5Preference': 'HTML5_PREF_WANTS',
        },
      },
    };

    final customHeaders = <String, String>{
      'Content-Type': 'application/json',
      'User-Agent': userAgent,
      'x-youtube-client-name': clientId,
      'x-youtube-client-version': clientVersion,
    };
    if (referer != null) {
      customHeaders['Referer'] = referer;
    }

    try {
      final response = await _postInnerTube(
        endpoint,
        payload,
        customHeaders: customHeaders,
      );
      if (response.statusCode != 200) {
        debugPrint('[InnerTube] $clientName returned status ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final playabilityStatus = data['playabilityStatus'] as Map<String, dynamic>?;
      if (playabilityStatus != null && playabilityStatus['status'] != 'OK') {
        debugPrint('[InnerTube] $clientName playabilityStatus: ${playabilityStatus['status']} - ${playabilityStatus['reason']}');
        return null;
      }

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

      // Check regular combined formats if no adaptive audio formats found
      if (audioFormats.isEmpty) {
        final regularFormats = (streamingData['formats'] as List<dynamic>?) ?? [];
        for (final fmt in regularFormats) {
          final formatMap = fmt as Map<String, dynamic>;
          final mimeType = formatMap['mimeType'] as String? ?? '';
          if (mimeType.contains('audio') || mimeType.contains('mp4')) {
            audioFormats.add(AudioFormat.fromJson(formatMap));
          }
        }
      }

      if (audioFormats.isEmpty) return null;

      // Prefer formats with direct unencrypted URLs first, then Opus (251) or M4A (140)
      audioFormats.sort((a, b) {
        final aHasUrl = (a.url != null && a.url!.isNotEmpty) ? 1 : 0;
        final bHasUrl = (b.url != null && b.url!.isNotEmpty) ? 1 : 0;
        if (aHasUrl != bHasUrl) return bHasUrl.compareTo(aHasUrl);

        if (a.itag == 251) return -1;
        if (b.itag == 251) return 1;
        if (a.itag == 140) return -1;
        if (b.itag == 140) return 1;
        return b.bitrate.compareTo(a.bitrate);
      });

      final selectedFormat = audioFormats.first;
      String streamUrl = selectedFormat.url ?? '';

      // Deobfuscate cipher only if URL is bundled inside signatureCipher
      if (streamUrl.isEmpty && selectedFormat.signatureCipher != null) {
        streamUrl = await _cipherResolver.resolveStreamUrl(
          rawUrl: '',
          signatureCipher: selectedFormat.signatureCipher,
        );
      }

      if (streamUrl.isEmpty) return null;

      final expiresInSeconds = int.tryParse(streamingData['expiresInSeconds']?.toString() ?? '21600') ?? 21600;
      final expiresAt = DateTime.now().add(Duration(seconds: expiresInSeconds));

      debugPrint('[InnerTube] Stream resolved successfully using $clientName (itag: ${selectedFormat.itag})');

      return StreamInfo(
        videoId: videoId,
        streamUrl: streamUrl,
        format: selectedFormat,
        expiresAt: expiresAt,
      );
    } catch (e) {
      debugPrint('[InnerTube] _fetchPlayerStream ($clientName) error: $e');
      return null;
    }
  }

  /// Piped API public proxy fallback for guaranteed streaming reliability.
  Future<StreamInfo?> _fetchPipedStream(String videoId) async {
    final instances = [
      'https://pipedapi.kavin.rocks',
      'https://api.piped.private.coffee',
      'https://piped-api.lunar.icu',
    ];

    for (final base in instances) {
      try {
        final res = await _httpClient.get(
          Uri.parse('$base/streams/$videoId'),
          headers: {'Accept': 'application/json'},
        ).timeout(const Duration(seconds: 4));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final audioStreams = (data['audioStreams'] as List<dynamic>?) ?? [];
          if (audioStreams.isNotEmpty) {
            audioStreams.sort((a, b) => ((b['bitrate'] ?? 0) as int).compareTo((a['bitrate'] ?? 0) as int));
            final best = audioStreams.first as Map<String, dynamic>;
            final streamUrl = best['url'] as String? ?? '';
            if (streamUrl.isNotEmpty) {
              debugPrint('[InnerTube] Stream resolved via Piped fallback ($base)');
              return StreamInfo(
                videoId: videoId,
                streamUrl: streamUrl,
                format: AudioFormat(
                  itag: best['itag'] ?? 140,
                  mimeType: best['mimeType'] ?? 'audio/mp4',
                  bitrate: best['bitrate'] ?? 128000,
                  contentLength: 0,
                  url: streamUrl,
                ),
                expiresAt: DateTime.now().add(const Duration(hours: 4)),
              );
            }
          }
        }
      } catch (_) {}
    }
    return null;
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
