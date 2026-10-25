/// Model representing extracted stream audio format details from YouTube.
class AudioFormat {
  final int itag;
  final String mimeType;
  final int bitrate;
  final int? audioSampleRate;
  final int? contentLength;
  final String? url;
  final String? signatureCipher;
  final double? loudnessDb;

  const AudioFormat({
    required this.itag,
    required this.mimeType,
    required this.bitrate,
    this.audioSampleRate,
    this.contentLength,
    this.url,
    this.signatureCipher,
    this.loudnessDb,
  });

  bool get isOpus => mimeType.contains('audio/webm') || mimeType.contains('opus');
  bool get isM4a => mimeType.contains('audio/mp4') || mimeType.contains('m4a');

  factory AudioFormat.fromJson(Map<String, dynamic> json) {
    return AudioFormat(
      itag: json['itag'] as int? ?? 0,
      mimeType: json['mimeType'] as String? ?? '',
      bitrate: json['bitrate'] as int? ?? 0,
      audioSampleRate: json['audioSampleRate'] != null
          ? int.tryParse(json['audioSampleRate'].toString())
          : null,
      contentLength: json['contentLength'] != null
          ? int.tryParse(json['contentLength'].toString())
          : null,
      url: json['url'] as String?,
      signatureCipher: (json['signatureCipher'] ?? json['cipher']) as String?,
      loudnessDb: (json['loudnessDb'] as num?)?.toDouble(),
    );
  }
}

/// Resolved stream information ready for playback.
class StreamInfo {
  final String videoId;
  final String streamUrl;
  final AudioFormat format;
  final DateTime expiresAt;

  const StreamInfo({
    required this.videoId,
    required this.streamUrl,
    required this.format,
    required this.expiresAt,
  });
}
