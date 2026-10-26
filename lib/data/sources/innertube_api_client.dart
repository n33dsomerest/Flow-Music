import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../core/constants/api_constants.dart';
import '../../core/crypto/cipher_resolver.dart';
import '../models/song_model.dart';
import '../models/stream_info_model.dart';

/// Client-Side Direct InnerTube API Client.
/// Communicates directly with YouTube Music endpoints using dynamic InnerTube API key,
/// multi-source fallback streaming (Invidious / Piped / Cobalt / ANDROID_TESTSUITE / ANDROID_MUSIC / IOS / TV),
/// and robust recursive JSON parser.
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
    bool includeVisitorData = true,
  }) async {
    final apiKey = await _ensureApiKey();
    final url = Uri.parse('$endpoint?key=$apiKey&prettyPrint=false');

    final headers = customHeaders != null
        ? Map<String, String>.from(customHeaders)
        : Map<String, String>.from(ApiConstants.defaultHeaders);

    headers['X-Goog-Api-Key'] = apiKey;
    if (includeVisitorData && _visitorData != null) {
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
  /// 1. ANDROID_VR InnerTube client (Oculus Quest 2: no BotGuard/PO-Token, direct clean URLs)
  /// 2. ANDROID_TESTSUITE InnerTube client (bypasses BotGuard / login requirements)
  /// 3. IOS InnerTube client (direct unencrypted AAC M4A)
  /// 4. TVHTML5_SIMPLY_EMBEDDED_PLAYER InnerTube client
  /// 5. WEB_EMBEDDED_PLAYER InnerTube client
  /// 6. Invidious API instances (proxied to prevent 403 Forbidden)
  /// 7. Piped API instances
  Future<StreamInfo?> getStreamInfo(String videoId) async {
    if (videoId.isEmpty) return null;

    // 1. Try ANDROID_VR (Oculus Quest 2: zero botguard blocks, pristine direct audio streams)
    var streamInfo = await _fetchPlayerStream(
      videoId,
      clientName: 'ANDROID_VR',
      clientVersion: '1.60.19',
      clientId: '28',
      userAgent: 'Mozilla/5.0 (Linux; Android 10; Quest 2) AppleWebKit/537.36 (KHTML, like Gecko) OculusBrowser/15.0.0.0 Safari/537.36',
      endpoint: 'https://www.youtube.com/youtubei/v1/player',
    );
    if (streamInfo != null) return streamInfo;

    // 2. Try ANDROID_TESTSUITE InnerTube client
    streamInfo = await _fetchPlayerStream(
      videoId,
      clientName: 'ANDROID_TESTSUITE',
      clientVersion: '1.9',
      clientId: '95',
      userAgent: 'com.google.android.youtube/19.29.35 (Linux; U; Android 11)',
      endpoint: 'https://www.youtube.com/youtubei/v1/player',
    );
    if (streamInfo != null) return streamInfo;

    // 3. Try IOS InnerTube client
    streamInfo = await _fetchPlayerStream(
      videoId,
      clientName: 'IOS',
      clientVersion: '19.29.1',
      clientId: '5',
      userAgent: 'com.google.ios.youtube/19.29.1 (iPhone16,2; U; CPU iOS 17_5_1 like Mac OS X)',
      endpoint: 'https://www.youtube.com/youtubei/v1/player',
    );
    if (streamInfo != null) return streamInfo;

    // 4. Try TVHTML5_SIMPLY_EMBEDDED_PLAYER InnerTube client
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

    // 5. Try WEB_EMBEDDED_PLAYER InnerTube client
    streamInfo = await _fetchPlayerStream(
      videoId,
      clientName: 'WEB_EMBEDDED_PLAYER',
      clientVersion: '1.20241015.01.00',
      clientId: '56',
      userAgent: ApiConstants.defaultUserAgent,
      endpoint: 'https://www.youtube.com/youtubei/v1/player',
      referer: 'https://www.youtube.com/',
    );
    if (streamInfo != null) return streamInfo;

    // 6. Try Invidious API instances (proxied to prevent IP-bound 403 Forbidden)
    streamInfo = await _fetchInvidiousStream(videoId);
    if (streamInfo != null) return streamInfo;

    // 7. Try Piped API instances
    return await _fetchPipedStream(videoId);
  }

  /// Invidious API public instance resolver (proxied to prevent 403 Forbidden).
  Future<StreamInfo?> _fetchInvidiousStream(String videoId) async {
    final instances = [
      'https://inv.tux.pizza',
      'https://invidious.nerdvpn.de',
      'https://invidious.jing.rocks',
      'https://iv.ggtyler.dev',
      'https://invidious.drgns.space',
      'https://yewtu.be',
    ];

    for (final base in instances) {
      try {
        final res = await _httpClient.get(
          Uri.parse('$base/api/v1/videos/$videoId'),
          headers: {'Accept': 'application/json'},
        ).timeout(const Duration(milliseconds: 3000));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final adaptiveFormats = (data['adaptiveFormats'] as List<dynamic>?) ?? [];
          final audioList = <Map<String, dynamic>>[];

          for (final fmt in adaptiveFormats) {
            final f = fmt as Map<String, dynamic>;
            final type = (f['type'] ?? f['mimeType'] ?? '') as String;
            if (type.startsWith('audio/')) {
              audioList.add(f);
            }
          }

          if (audioList.isNotEmpty) {
            audioList.sort((a, b) {
              final aItag = a['itag'] ?? 0;
              final bItag = b['itag'] ?? 0;
              if (aItag == 140) return -1;
              if (bItag == 140) return 1;
              if (aItag == 251) return -1;
              if (bItag == 251) return 1;
              return ((b['bitrate'] ?? 0) as num).compareTo((a['bitrate'] ?? 0) as num);
            });

            final selected = audioList.first;
            String streamUrl = selected['url'] as String? ?? '';
            if (streamUrl.startsWith('/')) {
              streamUrl = '$base$streamUrl';
            } else if (streamUrl.contains('googlevideo.com')) {
              // Route through Invidious proxy so phone does not get 403 Forbidden due to IP mismatch
              final query = Uri.parse(streamUrl).query;
              streamUrl = '$base/videoplayback?$query';
            }

            if (streamUrl.isNotEmpty) {
              debugPrint('[InnerTube] Stream resolved via Invidious ($base)');
              return StreamInfo(
                videoId: videoId,
                streamUrl: streamUrl,
                format: AudioFormat(
                  itag: selected['itag'] ?? 140,
                  mimeType: (selected['type'] ?? selected['mimeType'] ?? 'audio/mp4') as String,
                  bitrate: selected['bitrate'] ?? 128000,
                  contentLength: int.tryParse(selected['clen']?.toString() ?? '0') ?? 0,
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

  /// Piped API public instance resolver.
  Future<StreamInfo?> _fetchPipedStream(String videoId) async {
    final instances = [
      'https://pipedapi.tokhmi.xyz',
      'https://piped-api.garudalinux.org',
      'https://pipedapi.adminforge.de',
      'https://api.piped.privacydev.net',
      'https://pipedapi.drgns.space',
    ];

    for (final base in instances) {
      try {
        final res = await _httpClient.get(
          Uri.parse('$base/streams/$videoId'),
          headers: {'Accept': 'application/json'},
        ).timeout(const Duration(milliseconds: 3500));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final audioStreams = (data['audioStreams'] as List<dynamic>?) ?? [];
          if (audioStreams.isNotEmpty) {
            audioStreams.sort((a, b) => ((b['bitrate'] ?? 0) as int).compareTo((a['bitrate'] ?? 0) as int));
            final best = audioStreams.first as Map<String, dynamic>;
            final streamUrl = best['url'] as String? ?? '';
            if (streamUrl.isNotEmpty) {
              debugPrint('[InnerTube] Stream resolved via Piped ($base)');
              return StreamInfo(
                videoId: videoId,
                streamUrl: streamUrl,
                format: AudioFormat(
                  itag: best['itag'] ?? 140,
                  mimeType: best['mimeType'] ?? 'audio/mp4',
                  bitrate: best['bitrate'] ?? 128000,
                  contentLength: best['contentLength'] ?? 0,
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

  /// Cobalt API resolver for direct audio streams.
  Future<StreamInfo?> _fetchCobaltStream(String videoId) async {
    final instances = [
      'https://api.cobalt.tools/api/json',
      'https://cobalt.kwiatekm.pl/api/json',
    ];

    for (final endpoint in instances) {
      try {
        final res = await _httpClient.post(
          Uri.parse(endpoint),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'url': 'https://youtu.be/$videoId',
            'downloadMode': 'audio',
            'audioFormat': 'mp3',
          }),
        ).timeout(const Duration(milliseconds: 3500));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final streamUrl = data['url'] as String? ?? '';
          if (streamUrl.isNotEmpty) {
            debugPrint('[InnerTube] Stream resolved via Cobalt ($endpoint)');
            return StreamInfo(
              videoId: videoId,
              streamUrl: streamUrl,
              format: AudioFormat(
                itag: 140,
                mimeType: 'audio/mp3',
                bitrate: 128000,
                contentLength: 0,
                url: streamUrl,
              ),
              expiresAt: DateTime.now().add(const Duration(hours: 4)),
            );
          }
        }
      } catch (_) {}
    }
    return null;
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
          if (clientName == 'ANDROID' || clientName == 'ANDROID_MUSIC' || clientName == 'ANDROID_TESTSUITE')
            'androidSdkVersion': 30,
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
        if (clientName == 'TVHTML5_SIMPLY_EMBEDDED_PLAYER' || clientName == 'WEB_EMBEDDED_PLAYER')
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
      'contentCheckOk': true,
      'racyCheckOk': true,
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
        includeVisitorData: false,
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

      // Prefer formats with direct unencrypted URLs first, then M4A (140) or Opus (251)
      audioFormats.sort((a, b) {
        final aHasUrl = (a.url != null && a.url!.isNotEmpty) ? 1 : 0;
        final bHasUrl = (b.url != null && b.url!.isNotEmpty) ? 1 : 0;
        if (aHasUrl != bHasUrl) return bHasUrl.compareTo(aHasUrl);

        if (a.itag == 140) return -1;
        if (b.itag == 140) return 1;
        if (a.itag == 251) return -1;
        if (b.itag == 251) return 1;
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
        userAgent: userAgent,
      );
    } catch (e) {
      debugPrint('[InnerTube] _fetchPlayerStream ($clientName) error: $e');
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

      // Identify artist, album, and duration properly
      String artist = 'Unknown Artist';
      String? album;
      int durationSeconds = 0;

      if (flexColumns.length > 1) {
        final runs = flexColumns[1]['musicResponsiveListItemFlexColumnRenderer']
            ?['text']?['runs'] as List<dynamic>?;
        if (runs != null && runs.isNotEmpty) {
          // Check if first item is a type badge like "Song", "Video", "Single", "EP", "Album", or "เพลง"
          int artistIndex = 0;
          final firstText = (runs[0]['text'] as String? ?? '').trim().toLowerCase();
          final badgeKeywords = {'song', 'video', 'single', 'ep', 'album', 'เพลง', 'วิดีโอ'};

          if (badgeKeywords.contains(firstText) && runs.length > 2) {
            artistIndex = 2;
          }

          artist = runs[artistIndex]['text'] as String? ?? 'Unknown Artist';

          // Check album: usually after artist and bullet separator
          if (runs.length > artistIndex + 2) {
            final possibleAlbum = runs[artistIndex + 2]['text'] as String? ?? '';
            if (!possibleAlbum.contains(':') &&
                !possibleAlbum.contains('views') &&
                !possibleAlbum.contains('plays') &&
                !possibleAlbum.contains('การดู')) {
              album = possibleAlbum;
            }
          }

          // Search runs backwards for duration
          for (final run in runs.reversed) {
            final t = (run['text'] as String? ?? '').trim();
            if (t.contains(':') && RegExp(r'^\d+:\d+(:\d+)?$').hasMatch(t)) {
              durationSeconds = _parseDurationStringToSeconds(t);
              break;
            }
          }
        }
      }

      // Check fixedColumns if duration is still 0
      if (durationSeconds == 0 && renderer['fixedColumns'] != null) {
        final fixedCols = renderer['fixedColumns'] as List<dynamic>?;
        if (fixedCols != null && fixedCols.isNotEmpty) {
          final durRun = fixedCols[0]['musicResponsiveListItemFixedColumnRenderer']
              ?['text']?['runs']?[0]?['text'] as String?;
          if (durRun != null && durRun.contains(':')) {
            durationSeconds = _parseDurationStringToSeconds(durRun);
          }
        }
      }

      // Video ID extraction: check playlistItemData, title watchEndpoint, overlay, navigationEndpoint, and all runs
      String videoId = renderer['playlistItemData']?['videoId'] as String? ?? '';
      if (videoId.isEmpty) {
        videoId = titleRun?['navigationEndpoint']?['watchEndpoint']?['videoId'] as String? ?? '';
      }
      if (videoId.isEmpty) {
        videoId = renderer['overlay']?['musicItemThumbnailOverlayRenderer']
            ?['content']?['musicPlayButtonRenderer']
            ?['playNavigationEndpoint']?['watchEndpoint']?['videoId'] as String? ?? '';
      }
      if (videoId.isEmpty) {
        videoId = renderer['navigationEndpoint']?['watchEndpoint']?['videoId'] as String? ?? '';
      }
      if (videoId.isEmpty) {
        for (final col in flexColumns) {
          final runs = col['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'] as List<dynamic>?;
          if (runs != null) {
            for (final r in runs) {
              final vid = r['navigationEndpoint']?['watchEndpoint']?['videoId'] as String?;
              if (vid != null && vid.isNotEmpty) {
                videoId = vid;
                break;
              }
            }
          }
          if (videoId.isNotEmpty) break;
        }
      }

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
          durationSeconds: durationSeconds,
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

      String artist = 'Unknown Artist';
      String? album;
      final bylineRuns = (renderer['longBylineText']?['runs'] ?? renderer['shortBylineText']?['runs']) as List<dynamic>?;
      if (bylineRuns != null && bylineRuns.isNotEmpty) {
        int artistIdx = 0;
        final firstText = (bylineRuns[0]['text'] as String? ?? '').trim().toLowerCase();
        final badgeKeywords = {'song', 'video', 'single', 'ep', 'album', 'เพลง', 'วิดีโอ'};
        if (badgeKeywords.contains(firstText) && bylineRuns.length > 2) {
          artistIdx = 2;
        }
        artist = bylineRuns[artistIdx]['text'] as String? ?? 'Unknown Artist';
        if (bylineRuns.length > artistIdx + 2) {
          final possibleAlbum = bylineRuns[artistIdx + 2]['text'] as String? ?? '';
          if (!possibleAlbum.contains(':')) {
            album = possibleAlbum;
          }
        }
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
