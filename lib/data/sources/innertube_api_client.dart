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

  // In-memory stream cache to avoid repeated queries and rate limits
  static final Map<String, StreamInfo> _streamCache = {};

  static void clearCache(String videoId) {
    _streamCache.remove(videoId);
  }

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

  /// Search for songs, albums, and playlists on YouTube Music with Piped fallback.
  Future<List<SongModel>> search(String query, {String? filter}) async {
    final payload = ApiConstants.defaultClientContext();
    payload['query'] = query;
    if (filter != null) {
      payload['params'] = filter;
    }

    try {
      final response = await _postInnerTube(ApiConstants.searchEndpoint, payload);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final results = _extractSongsFromTree(data);
        if (results.isNotEmpty) return results;
      }
    } catch (e) {
      debugPrint('[InnerTube] InnerTube search error: $e');
    }

    // Fallback: search via Piped API
    return await _searchPiped(query);
  }

  /// Piped fallback search
  Future<List<SongModel>> _searchPiped(String query) async {
    final instances = [
      'https://pipedapi.adminforge.de',
      'https://pipedapi.kavin.rocks',
      'https://api.piped.private.coffee',
    ];

    for (final base in instances) {
      try {
        final url = Uri.parse('$base/search?q=${Uri.encodeComponent(query)}&filter=music_songs');
        final res = await _httpClient.get(url).timeout(const Duration(milliseconds: 3000));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final items = (data['items'] as List<dynamic>?) ?? [];
          final songs = <SongModel>[];

          for (final item in items) {
            final m = item as Map<String, dynamic>;
            final videoUrl = m['url'] as String? ?? '';
            final videoId = videoUrl.contains('v=')
                ? videoUrl.split('v=')[1].split('&')[0]
                : videoUrl.replaceFirst('/watch?v=', '');
            if (videoId.isNotEmpty) {
              songs.add(SongModel(
                id: videoId,
                title: m['title'] as String? ?? 'Unknown',
                artist: m['uploaderName'] as String? ?? 'Unknown Artist',
                durationSeconds: (m['duration'] as num?)?.toInt() ?? 0,
                thumbnailUrl: m['thumbnail'] as String? ?? '',
              ));
            }
          }
          if (songs.isNotEmpty) {
            debugPrint('[InnerTube] Search results retrieved via Piped fallback ($base)');
            return songs;
          }
        }
      } catch (_) {}
    }
    return [];
  }

  /// Get direct audio stream URL with Multi-Tier Hybrid Fallback:
  /// 0. In-memory cache check (zero latency)
  /// 1. Piped API instances with Fast Failover (M4A/AAC preferred, no BotGuard)
  /// 2. Cobalt Multi-Instance API (direct M4A/MP3 tunnel)
  /// 3. Invidious API instances (proxied to prevent IP-bound 403 Forbidden)
  /// 4. Direct InnerTube client (ANDROID_VR / WEB_EMBEDDED)
  Future<StreamInfo?> getStreamInfo(String videoId) async {
    if (videoId.isEmpty) return null;

    // 0. Check in-memory stream cache
    final cached = _streamCache[videoId];
    if (cached != null && DateTime.now().isBefore(cached.expiresAt.subtract(const Duration(minutes: 10)))) {
      debugPrint('[InnerTube] Returning in-memory cached stream for $videoId');
      return cached;
    }

    // 1. Tier 1: Piped API with Fast Failover (M4A/AAC preferred)
    var streamInfo = await _fetchPipedStream(videoId);
    if (streamInfo != null) {
      _streamCache[videoId] = streamInfo;
      return streamInfo;
    }

    // 2. Tier 2: Cobalt Multi-Instance API (High-quality direct audio tunnel)
    streamInfo = await _fetchCobaltStream(videoId);
    if (streamInfo != null) {
      _streamCache[videoId] = streamInfo;
      return streamInfo;
    }

    // 3. Tier 3: Invidious Public Instances (Proxied to bypass IP restrictions)
    streamInfo = await _fetchInvidiousStream(videoId);
    if (streamInfo != null) {
      _streamCache[videoId] = streamInfo;
      return streamInfo;
    }

    // 4. Tier 4: Direct InnerTube Embedded & Android clients as last resort
    streamInfo = await _fetchPlayerStream(
      videoId,
      clientName: 'ANDROID_VR',
      clientVersion: '1.60.19',
      clientId: '28',
      userAgent: 'Mozilla/5.0 (Linux; Android 10; Quest 2) AppleWebKit/537.36 (KHTML, like Gecko) OculusBrowser/15.0.0.0 Safari/537.36',
      endpoint: 'https://www.youtube.com/youtubei/v1/player',
    );
    if (streamInfo != null) {
      _streamCache[videoId] = streamInfo;
      return streamInfo;
    }

    return null;
  }

  /// Piped API public instance resolver with active failover list.
  Future<StreamInfo?> _fetchPipedStream(String videoId) async {
    final instances = [
      'https://pipedapi.adminforge.de',
      'https://pipedapi.kavin.rocks',
      'https://api.piped.private.coffee',
      'https://pipedapi.drgns.space',
      'https://pipedapi.leptons.xyz',
      'https://pipedapi.owo.si',
      'https://pipedapi.smnz.de',
    ];

    for (final base in instances) {
      try {
        final res = await _httpClient.get(
          Uri.parse('$base/streams/$videoId'),
          headers: {'Accept': 'application/json'},
        ).timeout(const Duration(milliseconds: 2500));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final audioStreams = (data['audioStreams'] as List<dynamic>?) ?? [];
          if (audioStreams.isNotEmpty) {
            // Sort: 1. M4A/AAC first, 2. Highest Bitrate, 3. Opus
            audioStreams.sort((a, b) {
              final aMap = a as Map<String, dynamic>;
              final bMap = b as Map<String, dynamic>;
              final aFmt = (aMap['format'] ?? aMap['mimeType'] ?? '').toString().toUpperCase();
              final bFmt = (bMap['format'] ?? bMap['mimeType'] ?? '').toString().toUpperCase();
              final aIsM4a = aFmt.contains('M4A') || aFmt.contains('MP4');
              final bIsM4a = bFmt.contains('M4A') || bFmt.contains('MP4');

              if (aIsM4a && !bIsM4a) return -1;
              if (!aIsM4a && bIsM4a) return 1;

              final aBitrate = (aMap['bitrate'] as num?)?.toInt() ?? 0;
              final bBitrate = (bMap['bitrate'] as num?)?.toInt() ?? 0;
              return bBitrate.compareTo(aBitrate);
            });

            final best = audioStreams.first as Map<String, dynamic>;
            final streamUrl = best['url'] as String? ?? '';
            if (streamUrl.isNotEmpty) {
              final mimeType = (best['mimeType'] as String?) ?? 'audio/mp4';
              final bitrate = (best['bitrate'] as num?)?.toInt() ?? 128000;
              final contentLength = int.tryParse(best['contentLength']?.toString() ?? '0') ?? 0;
              debugPrint('[InnerTube] Stream resolved via Piped ($base) [$mimeType]');
              return StreamInfo(
                videoId: videoId,
                streamUrl: streamUrl,
                format: AudioFormat(
                  itag: (best['itag'] as num?)?.toInt() ?? 140,
                  mimeType: mimeType,
                  bitrate: bitrate,
                  contentLength: contentLength,
                  url: streamUrl,
                ),
                expiresAt: DateTime.now().add(const Duration(hours: 4)),
              );
            }
          }
        }
      } catch (e) {
        debugPrint('[InnerTube] Piped ($base) error: $e');
      }
    }
    return null;
  }

  /// Cobalt API resolver for direct audio streams.
  Future<StreamInfo?> _fetchCobaltStream(String videoId) async {
    final instances = [
      'https://api.cobalt.tools',
      'https://cobalt.kwiatekm.pl/api/json',
      'https://cobalt-api.kellr.club/api/json',
      'https://dl.khann.me/api/json',
    ];

    for (final base in instances) {
      try {
        final endpoint = base.endsWith('/api/json') ? base : '$base/api/json';
        final res = await _httpClient.post(
          Uri.parse(endpoint),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'url': 'https://www.youtube.com/watch?v=$videoId',
            'downloadMode': 'audio',
            'audioFormat': 'm4a',
          }),
        ).timeout(const Duration(milliseconds: 3000));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final streamUrl = (data['url'] ?? data['stream'] ?? data['tunnel']) as String? ?? '';
          if (streamUrl.isNotEmpty) {
            debugPrint('[InnerTube] Stream resolved via Cobalt ($base)');
            return StreamInfo(
              videoId: videoId,
              streamUrl: streamUrl,
              format: AudioFormat(
                itag: 140,
                mimeType: 'audio/mp4',
                bitrate: 192000,
                contentLength: 0,
                url: streamUrl,
              ),
              expiresAt: DateTime.now().add(const Duration(hours: 4)),
            );
          }
        }
      } catch (e) {
        debugPrint('[InnerTube] Cobalt ($base) error: $e');
      }
    }
    return null;
  }

  /// Invidious API public instance resolver (proxied to prevent 403 Forbidden).
  Future<StreamInfo?> _fetchInvidiousStream(String videoId) async {
    final instances = [
      'https://invidious.nerdvpn.de',
      'https://invidious.jing.rocks',
      'https://iv.ggtyler.dev',
      'https://inv.tux.pizza',
      'https://invidious.drgns.space',
      'https://yewtu.be',
    ];

    for (final base in instances) {
      try {
        final res = await _httpClient.get(
          Uri.parse('$base/api/v1/videos/$videoId'),
          headers: {'Accept': 'application/json'},
        ).timeout(const Duration(milliseconds: 2500));

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
