/// API constants and configurations for YouTube Music InnerTube and metadata providers.
class ApiConstants {
  static const String youtubeMusicBaseUrl = 'https://music.youtube.com';
  static const String youtubeBaseUrl = 'https://www.youtube.com';
  static const String innerTubeApiBase = 'https://music.youtube.com/youtubei/v1';

  // InnerTube Endpoints
  static const String playerEndpoint = '$innerTubeApiBase/player';
  static const String searchEndpoint = '$innerTubeApiBase/search';
  static const String browseEndpoint = '$innerTubeApiBase/browse';
  static const String nextEndpoint = '$innerTubeApiBase/next';

  // LRCLIB Synced Lyrics Endpoint
  static const String lrclibBaseUrl = 'https://lrclib.net/api';
  static const String lrclibGetEndpoint = '$lrclibBaseUrl/get';
  static const String lrclibSearchEndpoint = '$lrclibBaseUrl/search';

  // InnerTube Client Header Configurations
  static const String webRemixClientName = 'WEB_REMIX';
  static const String webRemixClientVersion = '1.20241015.01.00';
  static const String clientNameHeader = '67'; // InnerTube ID for WEB_REMIX

  static const String defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36';

  static Map<String, String> get defaultHeaders => {
        'User-Agent': defaultUserAgent,
        'Accept': '*/*',
        'Accept-Language': 'en-US,en;q=0.9',
        'Content-Type': 'application/json',
        'x-youtube-client-name': clientNameHeader,
        'x-youtube-client-version': webRemixClientVersion,
        'x-origin': youtubeMusicBaseUrl,
        'Referer': '$youtubeMusicBaseUrl/',
      };

  static Map<String, dynamic> defaultClientContext({String hl = 'en', String gl = 'US'}) => {
        'context': {
          'client': {
            'clientName': webRemixClientName,
            'clientVersion': webRemixClientVersion,
            'hl': hl,
            'gl': gl,
            'utcOffsetMinutes': 0,
          },
          'user': {
            'lockedSafetyMode': false,
          },
        },
      };
}
