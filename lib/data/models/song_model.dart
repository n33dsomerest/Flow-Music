/// Model representing a playable track / song item.
class SongModel {
  final String id;
  final String title;
  final String artist;
  final String? album;
  final int durationSeconds;
  final String thumbnailUrl;
  final String? streamUrl;
  final bool isDownloaded;
  final DateTime? addedAt;

  const SongModel({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    required this.durationSeconds,
    required this.thumbnailUrl,
    this.streamUrl,
    this.isDownloaded = false,
    this.addedAt,
  });

  String get formattedDuration {
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  SongModel copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    int? durationSeconds,
    String? thumbnailUrl,
    String? streamUrl,
    bool? isDownloaded,
    DateTime? addedAt,
  }) {
    return SongModel(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      streamUrl: streamUrl ?? this.streamUrl,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'durationSeconds': durationSeconds,
      'thumbnailUrl': thumbnailUrl,
      'streamUrl': streamUrl,
      'isDownloaded': isDownloaded,
      'addedAt': addedAt?.toIso8601String(),
    };
  }

  factory SongModel.fromJson(Map<String, dynamic> json) {
    return SongModel(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String,
      album: json['album'] as String?,
      durationSeconds: json['durationSeconds'] as int? ?? 0,
      thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
      streamUrl: json['streamUrl'] as String?,
      isDownloaded: json['isDownloaded'] as bool? ?? false,
      addedAt: json['addedAt'] != null ? DateTime.parse(json['addedAt'] as String) : null,
    );
  }
}
