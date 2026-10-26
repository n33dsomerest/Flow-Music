import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../data/models/song_model.dart';
import '../../services/audio_player_service.dart';
import '../theme/app_theme.dart';
import 'now_playing_sheet.dart';

/// Floating Cyber-Glass Mini-Player bar shown above bottom navigation.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final audioService = AudioPlayerService();

    return StreamBuilder<SongModel?>(
      stream: audioService.currentSongStream,
      builder: (context, songSnap) {
        final song = songSnap.data ?? audioService.currentSong;
        if (song == null) return const SizedBox.shrink();

        return GestureDetector(
          onTap: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              backgroundColor: Colors.transparent,
              builder: (ctx) => NowPlayingSheet(song: song),
            );
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xE8181A28),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.14), width: 1.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: AppTheme.primary.withOpacity(0.12),
                  blurRadius: 14,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Column(
                  children: [
                    // Thin progress line along top of mini player
                    StreamBuilder<Duration>(
                      stream: audioService.positionStream,
                      builder: (context, posSnap) {
                        final pos = posSnap.data ?? Duration.zero;
                        return StreamBuilder<Duration?>(
                          stream: audioService.durationStream,
                          builder: (context, durSnap) {
                            final dur = durSnap.data ?? Duration(seconds: song.durationSeconds);
                            final progress = (dur.inMilliseconds > 0)
                                ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
                                : 0.0;

                            return LinearProgressIndicator(
                              value: progress,
                              minHeight: 2.2,
                              backgroundColor: Colors.transparent,
                              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryLight),
                            );
                          },
                        );
                      },
                    ),

                    // Main row: Thumbnail, Title/Artist, Play/Pause, Next
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          children: [
                            // Album Thumbnail with rounded corners & shadow
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: CachedNetworkImage(
                                imageUrl: song.thumbnailUrl,
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(
                                  width: 44,
                                  height: 44,
                                  color: AppTheme.surfaceHighlight,
                                  child: const Icon(CupertinoIcons.music_note, color: Colors.white60, size: 20),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Song Title & Artist
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    song.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    song.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Play/Pause Button
                            StreamBuilder<PlaybackStatus>(
                              stream: audioService.statusStream,
                              builder: (context, statusSnap) {
                                final status = statusSnap.data ?? PlaybackStatus.paused;
                                final isLoading = status == PlaybackStatus.loading;
                                final isPlaying = status == PlaybackStatus.playing;

                                if (isLoading) {
                                  return const SizedBox(
                                    width: 34,
                                    height: 34,
                                    child: Padding(
                                      padding: EdgeInsets.all(6),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        color: AppTheme.primaryLight,
                                      ),
                                    ),
                                  );
                                }

                                return IconButton(
                                  icon: Icon(
                                    isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                  onPressed: () {
                                    if (isPlaying) {
                                      audioService.pause();
                                    } else {
                                      audioService.play();
                                    }
                                  },
                                );
                              },
                            ),

                            // Skip Next Button
                            IconButton(
                              icon: const Icon(CupertinoIcons.forward_fill, color: Colors.white70, size: 20),
                              onPressed: () => audioService.skipToNext(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
