import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';

/// REA Engine: Reverse engineers YouTube Music's player JavaScript (base.js),
/// extracting and executing the signature decipher and n-sig throttling algorithms.
class CipherResolver {
  static final CipherResolver _instance = CipherResolver._internal();
  factory CipherResolver() => _instance;
  CipherResolver._internal();

  JavascriptRuntime? _jsRuntime;
  String? _cachedPlayerScript;
  String? _cachedPlayerUrl;
  DateTime? _playerScriptCachedAt;

  // Extracted JS decipher function names
  String? _sigDecipherFunctionName;
  String? _sigHelperObjectName;
  String? _nSigFunctionName;

  /// Initialize the embedded QuickJS runtime.
  Future<void> init() async {
    if (_jsRuntime == null) {
      _jsRuntime = getJavascriptRuntime();
    }
  }

  /// Clean up the JS runtime.
  void dispose() {
    _jsRuntime?.dispose();
    _jsRuntime = null;
  }

  /// Resolve a stream URL by deobfuscating signature cipher and throttling n-parameter.
  Future<String> resolveStreamUrl({
    required String rawUrl,
    String? signatureCipher,
  }) async {
    await init();
    String targetUrl = rawUrl;

    // 1. Resolve Signature Cipher if URL is bundled inside signatureCipher
    if (signatureCipher != null && signatureCipher.isNotEmpty) {
      final cipherParams = Uri.splitQueryString(signatureCipher);
      final rawStreamUrl = cipherParams['url'];
      final signature = cipherParams['s'];
      final sp = cipherParams['sp'] ?? 'sig';

      if (rawStreamUrl != null && signature != null) {
        final decryptedSig = await _deobfuscateSignature(signature);
        targetUrl = '$rawStreamUrl&$sp=${Uri.encodeComponent(decryptedSig)}';
      }
    }

    // 2. Resolve n-parameter throttling
    final uri = Uri.parse(targetUrl);
    final nParam = uri.queryParameters['n'];
    if (nParam != null && nParam.isNotEmpty) {
      final resolvedN = await _deobfuscateNParam(nParam);
      if (resolvedN != null && resolvedN.isNotEmpty && resolvedN != nParam) {
        final queryParams = Map<String, String>.from(uri.queryParameters);
        queryParams['n'] = resolvedN;
        targetUrl = uri.replace(queryParameters: queryParams).toString();
      }
    }

    return targetUrl;
  }

  /// Ensure latest YouTube player.js is fetched and loaded into JS runtime.
  Future<void> _ensurePlayerScriptLoaded() async {
    // If cached within the last 12 hours, reuse
    if (_cachedPlayerScript != null &&
        _playerScriptCachedAt != null &&
        DateTime.now().difference(_playerScriptCachedAt!).inHours < 12) {
      return;
    }

    try {
      // 1. Fetch YouTube Music homepage to locate current base.js player URL
      final homeResponse = await http.get(
        Uri.parse(ApiConstants.youtubeMusicBaseUrl),
        headers: ApiConstants.defaultHeaders,
      );

      final playerUrlMatch = RegExp(r'jsUrl":\s*"([^"]+base\.js)"')
          .firstMatch(homeResponse.body) ??
          RegExp(r'<script\s+src="([^"]*player[^"]*base\.js)"')
              .firstMatch(homeResponse.body);

      String? playerPath = playerUrlMatch?.group(1);
      playerPath ??= '/s/player/current/player_ias.vflset/en_US/base.js';

      final fullPlayerUrl = playerPath.startsWith('http')
          ? playerPath
          : '${ApiConstants.youtubeBaseUrl}$playerPath';

      _cachedPlayerUrl = fullPlayerUrl;

      // 2. Fetch the actual base.js script
      final scriptResponse = await http.get(Uri.parse(fullPlayerUrl));
      if (scriptResponse.statusCode == 200) {
        _cachedPlayerScript = scriptResponse.body;
        _playerScriptCachedAt = DateTime.now();
        _extractAndInjectCipherFunctions(_cachedPlayerScript!);
      }
    } catch (e) {
      debugPrint('[CipherResolver] Error fetching player script: $e');
    }
  }

  /// REA: Extract transformation functions and inject them into QuickJS.
  void _extractAndInjectCipherFunctions(String script) {
    if (_jsRuntime == null) return;

    try {
      // Find signature decipher function: e.g. a = a.split(""); obj.XX(a, 2); ... return a.join("")
      final sigFnMatch = RegExp(
        r'(?:function\s+(\w+)|(\w+)\s*=\s*function)\s*\(\s*(\w+)\s*\)\s*\{\s*\3\s*=\s*\3\.split\(\s*""\s*\);(.*?)\breturn\s+\3\.join\(\s*""\s*\)\s*\}',
      ).firstMatch(script);

      if (sigFnMatch != null) {
        _sigDecipherFunctionName = sigFnMatch.group(1) ?? sigFnMatch.group(2);
        final functionBody = sigFnMatch.group(4) ?? '';

        // Extract helper object name (e.g., "var XX = { reverse: function(a) {...} };")
        final helperObjMatch = RegExp(r'(\w+)\.\w+\(').firstMatch(functionBody);
        if (helperObjMatch != null) {
          _sigHelperObjectName = helperObjMatch.group(1);

          final objRegex = RegExp(
            'var\\s+${RegExp.escape(_sigHelperObjectName!)}\\s*=\\s*\\{([\\s\\S]*?)\\};',
          );
          final objMatch = objRegex.firstMatch(script);

          if (objMatch != null) {
            final objDeclaration = objMatch.group(0)!;
            final fnDeclaration = sigFnMatch.group(0)!;

            // Inject into QuickJS environment
            _jsRuntime!.evaluate(objDeclaration);
            _jsRuntime!.evaluate(fnDeclaration);
          }
        }
      }

      // Find n-sig throttling function:
      // Pattern: function(a){var b=a.split(""), c=... ; return b.join("")}
      final nFnMatch = RegExp(
        r'function\s*(\w+)?\s*\(\s*a\s*\)\s*\{var\s+b\s*=\s*a\.split\(""\)([\s\S]*?);return\s+b\.join\(""\)\};',
      ).firstMatch(script);

      if (nFnMatch != null) {
        final nFnBody = nFnMatch.group(0)!;
        _nSigFunctionName = 'solveNToken';
        _jsRuntime!.evaluate('var solveNToken = $nFnBody;');
      }
    } catch (e) {
      debugPrint('[CipherResolver] Extraction error: $e');
    }
  }

  /// Deobfuscate raw signature via embedded JS runtime.
  Future<String> _deobfuscateSignature(String signature) async {
    await _ensurePlayerScriptLoaded();

    if (_jsRuntime != null && _sigDecipherFunctionName != null) {
      try {
        final jsCall = '$_sigDecipherFunctionName(${jsonEncode(signature)})';
        final result = _jsRuntime!.evaluate(jsCall);
        if (!result.isError) {
          return result.stringResult;
        }
      } catch (e) {
        debugPrint('[CipherResolver] Signature JS evaluate error: $e');
      }
    }

    // Fallback: Return raw signature if decipher script unavailable
    return signature;
  }

  /// Deobfuscate n-parameter to prevent ~40KB/s audio streaming throttle.
  Future<String?> _deobfuscateNParam(String nParam) async {
    await _ensurePlayerScriptLoaded();

    if (_jsRuntime != null && _nSigFunctionName != null) {
      try {
        final jsCall = '$_nSigFunctionName(${jsonEncode(nParam)})';
        final result = _jsRuntime!.evaluate(jsCall);
        if (!result.isError && result.stringResult.isNotEmpty) {
          return result.stringResult;
        }
      } catch (e) {
        debugPrint('[CipherResolver] N-sig evaluate error: $e');
      }
    }

    return nParam;
  }
}
