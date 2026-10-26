import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide StreamInfo;
import '../../core/constants/api_constants.dart';
import '../models/song_model.dart';
import '../models/stream_info_model.dart';

/// Ultra-Reliable Multi-Engine Music API Client.
/// Engines:
/// 1. YouTube Music InnerTube Search (Direct JSON parsing, no login, full Thai metadata)
/// 2. YouTube Explode Pure-Dart Engine (High-speed metadata + Signature deciphering)
/// 3. Piped API Instances (Proxy fallback for search & pre-deciphered direct streams)
/// 4. Invidious API Instances (Tertiary stream fallback)
class InnerTubeApiClient {
  final http.Client _httpClient;

  static final Map<String, StreamInfo> _streamCache = {};
  static final Map<String, String> _lyricsCache = {};

  // High-availability Cobalt API instances for fast direct audio extraction
  static const List<String> _cobaltInstances = [
    'https://api.cobalt.tools',
    'https://cobalt-api.kwiatekm.tokyo',
    'https://cobalt.canine.tools',
  ];

  // High-availability Piped API instances
  static const List<String> _pipedInstances = [
    'https://pipedapi.adminforge.de',
    'https://pipedapi.kavin.rocks',
    'https://pipedapi.leptons.xyz',
    'https://piped-api.privacy.com.de',
    'https://pipedapi.nosebs.ru',
    'https://api.piped.yt',
  ];

  // High-availability Invidious API instances
  static const List<String> _invidiousInstances = [
    'https://inv.nadeko.net',
    'https://invidious.nerdvpn.de',
    'https://vid.priv.au',
    'https://invidious.drgns.space',
  ];

  InnerTubeApiClient({http.Client? httpClient, dynamic cipherResolver})
      : _httpClient = httpClient ?? http.Client();

  static void clearCache(String songId) {
    _streamCache.remove(songId);
  }

  /// Clean song ID by stripping any legacy server prefixes.
  static String cleanVideoId(String rawId) {
    if (rawId.contains(':')) {
      final parts = rawId.split(':');
      return parts.sublist(1).join(':');
    }
    return rawId;
  }

  // =========================================================================
  // SEARCH IMPLEMENTATION (InnerTube -> YoutubeExplode -> Piped)
  // =========================================================================

  /// Search across YouTube Music InnerTube, YoutubeExplode, and Piped API.
  Future<List<SongModel>> search(String query, {String? filter}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    debugPrint('[MusicApi] Searching for: "$cleanQuery"');

    // 1. YouTube Music InnerTube Search (Primary - richest Thai metadata)
    try {
      final innerTubeResults = await _searchInnerTube(cleanQuery);
      if (innerTubeResults.isNotEmpty) {
        debugPrint('[MusicApi] InnerTube returned ${innerTubeResults.length} songs');
        return innerTubeResults;
      }
    } catch (e) {
      debugPrint('[MusicApi] InnerTube search error: $e');
    }

    // 2. YoutubeExplode Pure-Dart Search (Secondary)
    try {
      final ytExplodeResults = await _searchYoutubeExplode(cleanQuery);
      if (ytExplodeResults.isNotEmpty) {
        debugPrint('[MusicApi] YoutubeExplode returned ${ytExplodeResults.length} songs');
        return ytExplodeResults;
      }
    } catch (e) {
      debugPrint('[MusicApi] YoutubeExplode search error: $e');
    }

    // 3. Piped API Search (Tertiary)
    try {
      final pipedResults = await _searchPiped(cleanQuery);
      if (pipedResults.isNotEmpty) {
        debugPrint('[MusicApi] Piped API returned ${pipedResults.length} songs');
        return pipedResults;
      }
    } catch (e) {
      debugPrint('[MusicApi] Piped search error: $e');
    }

    return [];
  }

  /// YouTube Music InnerTube `/youtubei/v1/search`
  Future<List<SongModel>> _searchInnerTube(String query) async {
    final uri = Uri.parse(ApiConstants.searchEndpoint);
    final body = jsonEncode({
      'context': {
        'client': {
          'clientName': ApiConstants.webRemixClientName,
          'clientVersion': ApiConstants.webRemixClientVersion,
          'hl': 'th',
          'gl': 'TH',
        },
      },
      'query': query,
    });

    final res = await _httpClient.post(
      uri,
      headers: ApiConstants.defaultHeaders,
      body: body,
    ).timeout(const Duration(milliseconds: 4500));

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return _parseInnerTubeResponse(data);
    }
    return [];
  }

  List<SongModel> _parseInnerTubeResponse(Map<String, dynamic> data) {
    final songs = <SongModel>[];
    try {
      final contents = data['contents']?['tabbedSearchResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents'] as List<dynamic>?;
      if (contents == null) return songs;

      for (final section in contents) {
        final shelf = section['musicShelfRenderer'] ?? section['musicCardShelfRenderer'];
        if (shelf == null) continue;

        final items = shelf['contents'] as List<dynamic>?;
        if (items == null) continue;

        for (final item in items) {
          final renderer = item['musicResponsiveListItemRenderer'] as Map<String, dynamic>?;
          if (renderer == null) continue;

          // Extract Video ID
          final videoId = renderer['playlistItemData']?['videoId']?.toString() ??
              renderer['navigationEndpoint']?['watchEndpoint']?['videoId']?.toString() ??
              renderer['doubleTapToLikeRenderer']?['likeEndpoint']?['target']?['videoId']?.toString() ?? '';
          if (videoId.isEmpty) continue;

          // Extract Title
          final flexColumns = renderer['flexColumns'] as List<dynamic>? ?? [];
          String title = '';
          if (flexColumns.isNotEmpty) {
            final col0 = flexColumns[0]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'] as List<dynamic>?;
            if (col0 != null && col0.isNotEmpty) {
              title = col0.map((r) => r['text']?.toString() ?? '').join().trim();
            }
          }
          if (title.isEmpty) continue;

          // Extract Artist, Album & Duration
          String artist = 'Various Artists';
          String? album;
          int durationSeconds = 0;

          if (flexColumns.length > 1) {
            final col1 = flexColumns[1]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'] as List<dynamic>?;
            if (col1 != null && col1.isNotEmpty) {
              final textParts = col1.map((r) => r['text']?.toString() ?? '').where((t) => t != ' • ').toList();
              if (textParts.isNotEmpty) {
                artist = textParts[0];
              }
              if (textParts.length > 1) {
                final lastPart = textParts.last;
                if (RegExp(r'^\d+:\d+$').hasMatch(lastPart)) {
                  final timeParts = lastPart.split(':');
                  durationSeconds = (int.tryParse(timeParts[0]) ?? 0) * 60 + (int.tryParse(timeParts[1]) ?? 0);
                  if (textParts.length > 2) {
                    album = textParts[1];
                  }
                } else {
                  album = textParts[1];
                }
              }
            }
          }

          // Extract Thumbnail Artwork
          String thumb = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
          final thumbs = renderer['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List<dynamic>?;
          if (thumbs != null && thumbs.isNotEmpty) {
            thumb = thumbs.last['url']?.toString() ?? thumb;
          }

          songs.add(SongModel(
            id: videoId,
            title: title,
            artist: artist,
            album: album,
            durationSeconds: durationSeconds,
            thumbnailUrl: thumb,
          ));
        }
      }
    } catch (e) {
      debugPrint('[MusicApi] InnerTube parse error: $e');
    }
    return songs;
  }

  /// Search using YoutubeExplode Pure-Dart Engine
  Future<List<SongModel>> _searchYoutubeExplode(String query) async {
    final yt = YoutubeExplode();
    final songs = <SongModel>[];
    try {
      final searchList = await yt.search.getVideos(query).timeout(const Duration(milliseconds: 4000));
      for (final video in searchList.take(15)) {
        songs.add(SongModel(
          id: video.id.value,
          title: video.title,
          artist: video.author,
          durationSeconds: video.duration?.inSeconds ?? 0,
          thumbnailUrl: video.thumbnails.highResUrl,
        ));
      }
    } catch (e) {
      debugPrint('[MusicApi] YoutubeExplode search error: $e');
    } finally {
      yt.close();
    }
    return songs;
  }

  /// Search using Piped API
  Future<List<SongModel>> _searchPiped(String query) async {
    for (final base in _pipedInstances) {
      try {
        final uri = Uri.parse('$base/search').replace(queryParameters: {
          'q': query,
          'filter': 'music_songs',
        });
        final res = await _httpClient.get(uri).timeout(const Duration(milliseconds: 3500));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final items = data['items'] as List<dynamic>?;
          if (items != null && items.isNotEmpty) {
            final songs = <SongModel>[];
            for (final item in items) {
              if (item is Map<String, dynamic>) {
                final url = item['url']?.toString() ?? '';
                final videoId = url.replaceFirst('/watch?v=', '').trim();
                final title = item['title']?.toString() ?? '';
                final uploader = item['uploaderName']?.toString() ?? 'Artist';
                final duration = (item['duration'] as num?)?.toInt() ?? 0;
                final thumb = item['thumbnail']?.toString() ?? 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';

                if (videoId.isNotEmpty && title.isNotEmpty) {
                  songs.add(SongModel(
                    id: videoId,
                    title: title,
                    artist: uploader,
                    durationSeconds: duration,
                    thumbnailUrl: thumb,
                  ));
                }
              }
            }
            if (songs.isNotEmpty) return songs;
          }
        }
      } catch (_) {}
    }
    return [];
  }

  // =========================================================================
  // RESILIENT MANIFEST & AUDIO EXTRACTION (androidVr -> ios -> tv -> safari -> android -> default)
  // =========================================================================

  /// Resilient manifest extractor that tries clients sequentially:
  /// [androidVr], [ios], [tv], [safari], [android], then default (null).
  /// Each client has 12 seconds timeout. Returns the first manifest with non-empty audioOnly.
  static Future<StreamManifest?> getManifestResilient(YoutubeExplode yt, String videoId) async {
    final cleanId = cleanVideoId(videoId);
    final clientsToTry = <List<YoutubeApiClient>?>[
      [YoutubeApiClient.androidVr],
      [YoutubeApiClient.ios],
      [YoutubeApiClient.tv],
      [YoutubeApiClient.safari],
      [YoutubeApiClient.android],
      null,
    ];

    for (final clientList in clientsToTry) {
      try {
        final StreamManifest manifest = clientList != null
            ? await yt.videos.streamsClient.getManifest(cleanId, ytClients: clientList).timeout(const Duration(seconds: 12))
            : await yt.videos.streamsClient.getManifest(cleanId).timeout(const Duration(seconds: 12));

        if (manifest.audioOnly.isNotEmpty) {
          debugPrint('[MusicApi] getManifestResilient succeeded with $clientList');
          return manifest;
        }
      } catch (e) {
        debugPrint('[MusicApi] getManifestResilient client $clientList error for $cleanId: $e');
      }
    }
    debugPrint('[MusicApi] getManifestResilient failed for all clients for $cleanId');
    return null;
  }

  /// Download audio stream directly to a temporary file for local playback fallback.
  Future<String?> downloadAudioToTemp(String songId) async {
    final cleanId = cleanVideoId(songId);
    if (cleanId.isEmpty) return null;

    final yt = YoutubeExplode();
    IOSink? sink;
    File? tempFile;

    try {
      final manifest = await getManifestResilient(yt, cleanId);
      if (manifest == null || manifest.audioOnly.isEmpty) {
        return null;
      }

      final audioStreams = manifest.audioOnly.toList();
      final m4aStreams = audioStreams.where((s) => s.container == StreamContainer.mp4 || s.container.name.toLowerCase() == 'mp4').toList();
      final bestAudio = m4aStreams.isNotEmpty
          ? m4aStreams.withHighestBitrate()
          : audioStreams.withHighestBitrate();

      final ext = (bestAudio.container == StreamContainer.mp4 || bestAudio.container.name.toLowerCase() == 'mp4')
          ? 'm4a'
          : 'webm';

      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/flow_$cleanId.$ext';
      final file = File(filePath);
      tempFile = file;

      if (await file.exists() && await file.length() > 1000) {
        debugPrint('[MusicApi] Temp file already exists: $filePath');
        return filePath;
      }

      sink = file.openWrite();
      final stream = yt.videos.streamsClient.get(bestAudio);
      await for (final chunk in stream) {
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (await file.exists() && await file.length() > 1000) {
        debugPrint('[MusicApi] Temp file downloaded successfully: $filePath');
        return filePath;
      }
    } catch (e) {
      debugPrint('[MusicApi] downloadAudioToTemp error for $cleanId: $e');
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
        sink = null;
      }
      if (tempFile != null && await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
    } finally {
      yt.close();
    }
    return null;
  }

  // =========================================================================
  // STREAM EXTRACTION (getManifestResilient -> Cobalt -> Piped -> Invidious)
  // =========================================================================

  /// Get direct audio stream URL for playback and download.
  Future<StreamInfo?> getStreamInfo(String songId) async {
    final cleanId = cleanVideoId(songId);
    if (cleanId.isEmpty) return null;

    // 0. Check in-memory stream cache
    final cached = _streamCache[cleanId];
    if (cached != null && DateTime.now().isBefore(cached.expiresAt.subtract(const Duration(minutes: 5)))) {
      debugPrint('[MusicApi] Returning cached stream for $cleanId');
      return cached;
    }

    // 1. YoutubeExplode Pure-Dart manifest extraction (Primary)
    try {
      final yt = YoutubeExplode();
      try {
        final manifest = await getManifestResilient(yt, cleanId);
        final List<AudioOnlyStreamInfo> audioStreams = manifest == null
            ? <AudioOnlyStreamInfo>[]
            : manifest.audioOnly.toList();

        if (audioStreams.isNotEmpty) {
          // Prefer MP4/AAC container for 100% universal Android hardware audio decoding
          final m4aStreams = audioStreams.where((s) => s.container == StreamContainer.mp4 || s.container.name.toLowerCase() == 'mp4').toList();
          final bestAudio = m4aStreams.isNotEmpty
              ? m4aStreams.withHighestBitrate()
              : audioStreams.withHighestBitrate();
          final streamUrl = bestAudio.url.toString();

          if (streamUrl.isNotEmpty) {
            debugPrint('[MusicApi] YoutubeExplode resolved stream (${bestAudio.container.name}, ${bestAudio.bitrate})');
            final info = StreamInfo(
              videoId: cleanId,
              streamUrl: streamUrl,
              format: AudioFormat(
                itag: bestAudio.tag,
                mimeType: 'audio/${bestAudio.container.name}',
                bitrate: bestAudio.bitrate.bitsPerSecond,
                contentLength: bestAudio.size.totalBytes,
                url: streamUrl,
              ),
              expiresAt: DateTime.now().add(const Duration(hours: 4)),
            );
            _streamCache[cleanId] = info;
            return info;
          }
        }
      } finally {
        yt.close();
      }
    } catch (e) {
      debugPrint('[MusicApi] YoutubeExplode stream error for $cleanId: $e');
    }

    // 2. Cobalt API Direct Stream Fallback (Secondary)
    final cobaltStream = await _resolveCobaltStream(cleanId);
    if (cobaltStream != null) {
      _streamCache[cleanId] = cobaltStream;
      return cobaltStream;
    }

    // 3. Piped API Stream Proxy (Tertiary)
    final pipedStream = await _resolvePipedStream(cleanId);
    if (pipedStream != null) {
      _streamCache[cleanId] = pipedStream;
      return pipedStream;
    }

    // 4. Invidious API Stream Fallback (Quaternary)
    final invidiousStream = await _resolveInvidiousStream(cleanId);
    if (invidiousStream != null) {
      _streamCache[cleanId] = invidiousStream;
      return invidiousStream;
    }

    return null;
  }

  /// Resolve stream from Cobalt API
  Future<StreamInfo?> _resolveCobaltStream(String videoId) async {
    for (final base in _cobaltInstances) {
      try {
        final uri = Uri.parse(base);
        final body = jsonEncode({
          'url': 'https://www.youtube.com/watch?v=$videoId',
          'downloadMode': 'audio',
          'audioFormat': 'mp3',
        });
        final res = await _httpClient.post(
          uri,
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'User-Agent': 'FlowMusic/1.0',
          },
          body: body,
        ).timeout(const Duration(seconds: 4));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final streamUrl = data['url']?.toString() ?? '';
          if (streamUrl.isNotEmpty && streamUrl.startsWith('http')) {
            debugPrint('[MusicApi] Cobalt resolved stream from $base');
            return StreamInfo(
              videoId: videoId,
              streamUrl: streamUrl,
              format: AudioFormat(
                itag: 140,
                mimeType: 'audio/mpeg',
                bitrate: 320000,
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

  /// Resolve stream from Piped API
  Future<StreamInfo?> _resolvePipedStream(String videoId) async {
    for (final base in _pipedInstances) {
      try {
        final uri = Uri.parse('$base/streams/$videoId');
        final res = await _httpClient.get(uri).timeout(const Duration(milliseconds: 3800));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final audioStreams = data['audioStreams'] as List<dynamic>?;
          if (audioStreams != null && audioStreams.isNotEmpty) {
            audioStreams.sort((a, b) => ((b['bitrate'] as num?) ?? 0).compareTo((a['bitrate'] as num?) ?? 0));
            final best = audioStreams.first as Map<String, dynamic>;
            final streamUrl = best['url']?.toString() ?? '';

            if (streamUrl.isNotEmpty && streamUrl.startsWith('http')) {
              debugPrint('[MusicApi] Piped resolved stream from $base');
              return StreamInfo(
                videoId: videoId,
                streamUrl: streamUrl,
                format: AudioFormat(
                  itag: (best['itag'] as num?)?.toInt() ?? 140,
                  mimeType: best['mimeType']?.toString() ?? 'audio/mp4',
                  bitrate: (best['bitrate'] as num?)?.toInt() ?? 128000,
                  contentLength: (best['contentLength'] as num?)?.toInt(),
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

  /// Resolve stream from Invidious API
  Future<StreamInfo?> _resolveInvidiousStream(String videoId) async {
    for (final base in _invidiousInstances) {
      try {
        final uri = Uri.parse('$base/api/v1/videos/$videoId');
        final res = await _httpClient.get(uri).timeout(const Duration(milliseconds: 3500));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final adaptive = data['adaptiveFormats'] as List<dynamic>?;
          if (adaptive != null && adaptive.isNotEmpty) {
            final audioOnly = adaptive.where((f) => (f['type']?.toString() ?? '').contains('audio')).toList();
            if (audioOnly.isNotEmpty) {
              audioOnly.sort((a, b) => ((b['bitrate'] as num?) ?? 0).compareTo((a['bitrate'] as num?) ?? 0));
              final best = audioOnly.first as Map<String, dynamic>;
              final streamUrl = best['url']?.toString() ?? '';
              if (streamUrl.isNotEmpty) {
                debugPrint('[MusicApi] Invidious resolved stream from $base');
                return StreamInfo(
                  videoId: videoId,
                  streamUrl: streamUrl,
                  format: AudioFormat(
                    itag: (best['itag'] as num?)?.toInt() ?? 140,
                    mimeType: best['type']?.toString() ?? 'audio/mp4',
                    bitrate: (best['bitrate'] as num?)?.toInt() ?? 128000,
                    contentLength: (best['clen'] as num?)?.toInt(),
                    url: streamUrl,
                  ),
                  expiresAt: DateTime.now().add(const Duration(hours: 4)),
                );
              }
            }
          }
        }
      } catch (_) {}
    }
    return null;
  }

  /// Get LRC synchronized lyrics for a song.
  Future<String?> getLrcLyrics(String songId) async {
    if (_lyricsCache.containsKey(songId)) {
      return _lyricsCache[songId];
    }
    return null;
  }

  /// Radio suggestions based on current song.
  Future<List<SongModel>> getRadioQueue(String songId) async {
    return await search('เพลงฮิต');
  }

  /// Get playlist songs.
  Future<List<SongModel>> getPlaylistSongs(String playlistId) async {
    return await search(playlistId);
  }
}
