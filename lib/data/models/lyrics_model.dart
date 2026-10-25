/// Represents a single timed lyric line in synced lyrics.
class LyricLine {
  final Duration timestamp;
  final String text;

  const LyricLine({required this.timestamp, required this.text});

  @override
  String toString() => '[${timestamp.inMinutes}:${(timestamp.inSeconds % 60).toString().padLeft(2, '0')}] $text';
}

/// Represents the full lyrics payload for a song.
class LyricsModel {
  final String songTitle;
  final String artistName;
  final bool isSynced;
  final List<LyricLine> lines;
  final String? plainLyrics;

  const LyricsModel({
    required this.songTitle,
    required this.artistName,
    required this.isSynced,
    required this.lines,
    this.plainLyrics,
  });

  /// Parse standard LRC text into a list of [LyricLine].
  factory LyricsModel.fromLrc({
    required String title,
    required String artist,
    required String lrcContent,
  }) {
    final List<LyricLine> parsedLines = [];
    final regex = RegExp(r'\[(\d{2}):(\d{2})\.?(\d{2,3})?\](.*)');

    for (final line in lrcContent.split('\n')) {
      final match = regex.firstMatch(line.trim());
      if (match != null) {
        final minutes = int.tryParse(match.group(1) ?? '0') ?? 0;
        final seconds = int.tryParse(match.group(2) ?? '0') ?? 0;
        final millisStr = match.group(3) ?? '0';
        final millis = int.tryParse(millisStr.padRight(3, '0').substring(0, 3)) ?? 0;
        final text = match.group(4)?.trim() ?? '';

        final duration = Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: millis,
        );

        if (text.isNotEmpty) {
          parsedLines.add(LyricLine(timestamp: duration, text: text));
        }
      }
    }

    parsedLines.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return LyricsModel(
      songTitle: title,
      artistName: artist,
      isSynced: parsedLines.isNotEmpty,
      lines: parsedLines,
      plainLyrics: lrcContent,
    );
  }

  factory LyricsModel.plain({
    required String title,
    required String artist,
    required String text,
  }) {
    return LyricsModel(
      songTitle: title,
      artistName: artist,
      isSynced: false,
      lines: const [],
      plainLyrics: text,
    );
  }
}
