import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../data/models/song_model.dart';
import '../../services/audio_player_service.dart';
import '../theme/app_theme.dart';
import 'now_playing_sheet.dart';

/// Floating Mini-Player bar shown above bottom navigation.
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
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            height: 64,
            decoration: BoxDecoration(
              color: AppTheme.surfaceLight.withOpacity(0.85),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black38,
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
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
                              minHeight: 2.0,
                              backgroundColor: Colors.transparent,
                              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
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
                            // Album Thumbnail
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: CachedNetworkImage(
                                imageUrl: song.thumbnailUrl,
                                width: 46,
                                height: 46,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(
                                  width: 46,
                                  height: 46,
                                  color: AppTheme.surface,
                                  child: const Icon(CupertinoIcons.music_note, color: Colors.white60),
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
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    song.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white60,
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
                                    width: 32,
                                    height: 32,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  );
                                }

                                return IconButton(
                                  icon: Icon(
                                    isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                                    color: Colors.white,
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
                              icon: const Icon(CupertinoIcons.forward_fill, color: Colors.white, size: 20),
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
