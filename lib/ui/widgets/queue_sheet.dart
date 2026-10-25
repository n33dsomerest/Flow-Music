import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../data/models/song_model.dart';
import '../../services/audio_player_service.dart';
import '../theme/app_theme.dart';

/// Bottom sheet displaying the current playing queue and upcoming Endless Radio tracks.
class QueueBottomSheet extends StatelessWidget {
  const QueueBottomSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final audioService = AudioPlayerService();

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'คิวเพลงที่กำลังเล่น',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                Text(
                  '${audioService.queue.length} เพลง',
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12),
          Expanded(
            child: StreamBuilder<List<SongModel>>(
              stream: audioService.queueStream,
              initialData: audioService.queue,
              builder: (context, snapshot) {
                final queue = snapshot.data ?? [];
                final currentSong = audioService.currentSong;

                if (queue.isEmpty) {
                  return const Center(
                    child: Text('ไม่มีเพลงในคิว', style: TextStyle(color: Colors.white54)),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: queue.length,
                  itemBuilder: (context, index) {
                    final song = queue[index];
                    final isCurrent = song.id == currentSong?.id;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isCurrent ? AppTheme.primary.withOpacity(0.18) : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: isCurrent ? Border.all(color: AppTheme.primary.withOpacity(0.4)) : null,
                      ),
                      child: ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: song.thumbnailUrl,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                          ),
                        ),
                        title: Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isCurrent ? AppTheme.secondary : Colors.white,
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                        trailing: isCurrent
                            ? const Icon(CupertinoIcons.waveform, color: AppTheme.secondary, size: 20)
                            : const Icon(CupertinoIcons.bars, color: Colors.white24, size: 20),
                        onTap: () {
                          audioService.playPlaylist(queue, initialIndex: index);
                          Navigator.pop(context);
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
