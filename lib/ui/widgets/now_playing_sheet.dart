import 'dart:async';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../data/models/lyrics_model.dart';
import '../../data/models/song_model.dart';
import '../../data/sources/lyrics_client.dart';
import '../../services/audio_player_service.dart';
import '../../services/download_cache_service.dart';
import '../theme/app_theme.dart';
import 'queue_sheet.dart';
import 'sleep_timer_dialog.dart';

/// Full-screen Glassmorphic Now Playing View with Synced Lyrics support.
class NowPlayingSheet extends StatefulWidget {
  final SongModel song;

  const NowPlayingSheet({super.key, required this.song});

  @override
  State<NowPlayingSheet> createState() => _NowPlayingSheetState();
}

class _NowPlayingSheetState extends State<NowPlayingSheet> with SingleTickerProviderStateMixin {
  final AudioPlayerService _audioService = AudioPlayerService();
  final LyricsClient _lyricsClient = LyricsClient();
  final DownloadCacheService _downloadService = DownloadCacheService();

  late SongModel _currentSong;
  StreamSubscription<SongModel?>? _songSubscription;

  late TabController _tabController;
  LyricsModel? _lyrics;
  bool _isLoadingLyrics = true;
  bool _isDownloaded = false;
  final ScrollController _lyricsScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _currentSong = widget.song;
    _tabController = TabController(length: 2, vsync: this);
    _loadLyrics();
    _checkDownloadStatus();

    _songSubscription = _audioService.currentSongStream.listen((song) {
      if (song != null && song.id != _currentSong.id && mounted) {
        setState(() {
          _currentSong = song;
        });
        _loadLyrics();
        _checkDownloadStatus();
      }
    });
  }

  Future<void> _checkDownloadStatus() async {
    final downloaded = await _downloadService.isSongDownloaded(_currentSong.id);
    if (mounted) setState(() => _isDownloaded = downloaded);
  }

  Future<void> _loadLyrics() async {
    setState(() => _isLoadingLyrics = true);
    final lyrics = await _lyricsClient.getLyrics(_currentSong);
    if (mounted) {
      setState(() {
        _lyrics = lyrics;
        _isLoadingLyrics = false;
      });
    }
  }

  @override
  void dispose() {
    _songSubscription?.cancel();
    _tabController.dispose();
    _lyricsScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Dynamic Blurred Background from Album Cover
          Positioned.fill(
            child: CachedNetworkImage(
              imageUrl: _currentSong.thumbnailUrl,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(color: AppTheme.background),
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 45, sigmaY: 45),
              child: Container(
                color: Colors.black.withOpacity(0.65),
              ),
            ),
          ),

          // Main Content
          SafeArea(
            child: Column(
              children: [
                // Top Header (Collapse button & Mode Tabs)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(CupertinoIcons.chevron_down, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: TabBar(
                          controller: _tabController,
                          isScrollable: true,
                          indicatorColor: AppTheme.primary,
                          indicatorWeight: 3,
                          labelColor: Colors.white,
                          unselectedLabelColor: Colors.white60,
                          tabs: const [
                            Tab(text: 'Player'),
                            Tab(text: 'Lyrics'),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(CupertinoIcons.moon_zzz, color: Colors.white, size: 22),
                            tooltip: 'ตั้งเวลาปิด',
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (ctx) => const SleepTimerDialog(),
                              );
                            },
                          ),
                          StreamBuilder<Map<String, double>>(
                            stream: _downloadService.downloadProgressStream,
                            builder: (context, snapshot) {
                              final progress = _downloadService.getDownloadProgress(_currentSong.id);
                              final isDownloading = progress != null;

                              if (isDownloading) {
                                final pct = (progress * 100).toInt();
                                return Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: AppTheme.secondary.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: AppTheme.secondary.withOpacity(0.6), width: 1.2),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          value: progress > 0 ? progress : null,
                                          strokeWidth: 2,
                                          color: AppTheme.secondary,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '$pct%',
                                        style: const TextStyle(
                                          color: AppTheme.secondary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }

                              return IconButton(
                                icon: Icon(
                                  _isDownloaded ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.arrow_down_circle,
                                  color: _isDownloaded ? AppTheme.secondary : Colors.white,
                                  size: 22,
                                ),
                                tooltip: _isDownloaded ? 'ดาวน์โหลดแล้ว' : 'ดาวน์โหลดเพลง',
                                onPressed: () async {
                                  if (_isDownloaded) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('เพลงนี้ดาวน์โหลดเก็บไว้ใน /storage/emulated/0/Music แล้ว')),
                                    );
                                    return;
                                  }
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('เริ่มดาวน์โหลดเพลง... กำลังโหลดข้อมูล')),
                                  );
                                  final ok = await _downloadService.downloadSong(
                                    _currentSong,
                                    onProgress: (_) {
                                      if (mounted) setState(() {});
                                    },
                                  );
                                  if (mounted) {
                                    setState(() => _isDownloaded = ok);
                                    if (ok) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('ดาวน์โหลดเสร็จสมบูรณ์ 100%! บันทึกที่ /storage/emulated/0/Music')),
                                      );
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('ดาวน์โหลดไม่สำเร็จ กรุณาลองใหม่อีกครั้ง')),
                                      );
                                    }
                                  }
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Tab Content: Album Art View vs Synced Lyrics View
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildAlbumArtView(),
                      _buildLyricsView(),
                    ],
                  ),
                ),

                // Controls & Seek Bar
                _buildPlaybackControls(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumArtView() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 20.0),
      child: Center(
        child: AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withOpacity(0.35),
                  blurRadius: 36,
                  spreadRadius: -4,
                  offset: const Offset(0, 16),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.6),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: CachedNetworkImage(
                imageUrl: _currentSong.thumbnailUrl,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLyricsView() {
    if (_isLoadingLyrics) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    if (_lyrics == null || (!_lyrics!.isSynced && (_lyrics!.plainLyrics == null || _lyrics!.plainLyrics!.isEmpty))) {
      return const Center(
        child: Text(
          'ไม่มีเนื้อเพลงสำหรับเพลงนี้',
          style: TextStyle(color: Colors.white54, fontSize: 16),
        ),
      );
    }

    if (!_lyrics!.isSynced) {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Text(
          _lyrics!.plainLyrics ?? '',
          style: const TextStyle(color: Colors.white70, fontSize: 18, height: 1.8),
          textAlign: TextAlign.center,
        ),
      );
    }

    return StreamBuilder<Duration>(
      stream: _audioService.positionStream,
      builder: (context, snapshot) {
        final currentPosition = snapshot.data ?? Duration.zero;

        return ListView.builder(
          controller: _lyricsScrollController,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          itemCount: _lyrics!.lines.length,
          itemBuilder: (context, index) {
            final line = _lyrics!.lines[index];
            final nextTimestamp = index + 1 < _lyrics!.lines.length
                ? _lyrics!.lines[index + 1].timestamp
                : const Duration(hours: 1);

            final isActive = currentPosition >= line.timestamp && currentPosition < nextTimestamp;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                style: TextStyle(
                  fontSize: isActive ? 24 : 18,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                  color: isActive ? Colors.white : Colors.white30,
                  height: 1.4,
                ),
                child: Text(
                  line.text,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPlaybackControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        children: [
          // Title & Artist
          Text(
            _currentSong.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _currentSong.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, color: Colors.white70),
          ),
          const SizedBox(height: 16),

          // Seek Bar
          StreamBuilder<Duration>(
            stream: _audioService.positionStream,
            builder: (context, posSnap) {
              final position = posSnap.data ?? Duration.zero;
              return StreamBuilder<Duration?>(
                stream: _audioService.durationStream,
                builder: (context, durSnap) {
                  final duration = durSnap.data ?? Duration(seconds: _currentSong.durationSeconds);
                  final maxSec = duration.inSeconds > 0 ? duration.inSeconds.toDouble() : 1.0;
                  final currentSec = position.inSeconds.toDouble().clamp(0.0, maxSec);

                  return Column(
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          trackHeight: 3,
                          activeTrackColor: Colors.white,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.white,
                        ),
                        child: Slider(
                          value: currentSec,
                          min: 0,
                          max: maxSec,
                          onChanged: (val) {
                            _audioService.seek(Duration(seconds: val.toInt()));
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatTime(position),
                              style: const TextStyle(color: Colors.white60, fontSize: 12),
                            ),
                            Text(
                              _formatTime(duration),
                              style: const TextStyle(color: Colors.white60, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),

          const SizedBox(height: 8),

          // Main Player Buttons (Shuffle, Prev, Play/Pause, Next, Queue)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                iconSize: 22,
                icon: const Icon(CupertinoIcons.shuffle, color: Colors.white60),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('สุ่มเล่นเพลงในคิว')),
                  );
                },
              ),
              IconButton(
                iconSize: 36,
                icon: const Icon(CupertinoIcons.backward_fill, color: Colors.white),
                onPressed: () => _audioService.skipToPrevious(),
              ),
              StreamBuilder<PlaybackStatus>(
                stream: _audioService.statusStream,
                builder: (context, snapshot) {
                  final status = snapshot.data ?? PlaybackStatus.paused;
                  final isLoading = status == PlaybackStatus.loading;
                  final isPlaying = status == PlaybackStatus.playing;

                  if (isLoading) {
                    return const SizedBox(
                      width: 64,
                      height: 64,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                    );
                  }

                  return Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppTheme.primaryGradient,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withOpacity(0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: IconButton(
                      iconSize: 34,
                      icon: Icon(
                        isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        if (isPlaying) {
                          _audioService.pause();
                        } else {
                          _audioService.play();
                        }
                      },
                    ),
                  );
                },
              ),
              IconButton(
                iconSize: 36,
                icon: const Icon(CupertinoIcons.forward_fill, color: Colors.white),
                onPressed: () => _audioService.skipToNext(),
              ),
              IconButton(
                iconSize: 22,
                icon: const Icon(CupertinoIcons.list_bullet, color: Colors.white60),
                tooltip: 'ดูคิวเพลง',
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (ctx) => const QueueBottomSheet(),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _formatTime(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
