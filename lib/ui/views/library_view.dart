import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../data/models/song_model.dart';
import '../../services/audio_player_service.dart';
import '../../services/download_cache_service.dart';
import '../../services/local_playlist_service.dart';
import '../theme/app_theme.dart';
import '../widgets/now_playing_sheet.dart';

/// Cyber-Glass Library View with Offline Downloads and Playlists.
class LibraryView extends StatefulWidget {
  const LibraryView({super.key});

  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<LibraryView> with SingleTickerProviderStateMixin {
  final DownloadCacheService _downloadService = DownloadCacheService();
  final LocalPlaylistService _playlistService = LocalPlaylistService();
  final AudioPlayerService _audioService = AudioPlayerService();

  late TabController _tabController;
  List<SongModel> _downloadedSongs = [];
  List<LocalPlaylist> _playlists = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final downloads = await _downloadService.getDownloadedSongs();
    final playlists = await _playlistService.getPlaylists();
    if (mounted) {
      setState(() {
        _downloadedSongs = downloads;
        _playlists = playlists;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Modern Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ShaderMask(
                    shaderCallback: (bounds) => AppTheme.primaryGradient.createShader(bounds),
                    child: const Text(
                      'คลังเพลงของคุณ',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _showPlaylistActionMenu(),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: AppTheme.glassDecoration(
                        borderRadius: 14,
                        color: Colors.white.withOpacity(0.06),
                      ),
                      child: const Icon(CupertinoIcons.plus, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),

            // Modern iOS Glass Segmented Switcher
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight.withOpacity(0.6),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _tabController.animateTo(0),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          gradient: _tabController.index == 0 ? AppTheme.primaryGradient : null,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                CupertinoIcons.arrow_down_circle_fill,
                                size: 16,
                                color: _tabController.index == 0 ? Colors.white : Colors.white60,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'ออฟไลน์ (${_downloadedSongs.length})',
                                style: TextStyle(
                                  color: _tabController.index == 0 ? Colors.white : Colors.white60,
                                  fontWeight: _tabController.index == 0 ? FontWeight.bold : FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _tabController.animateTo(1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          gradient: _tabController.index == 1 ? AppTheme.primaryGradient : null,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                CupertinoIcons.music_albums_fill,
                                size: 16,
                                color: _tabController.index == 1 ? Colors.white : Colors.white60,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'เพลย์ลิสต์ (${_playlists.length})',
                                style: TextStyle(
                                  color: _tabController.index == 1 ? Colors.white : Colors.white60,
                                  fontWeight: _tabController.index == 1 ? FontWeight.bold : FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Tab Views
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryLight))
                  : TabBarView(
                      controller: _tabController,
                      physics: const BouncingScrollPhysics(),
                      children: [
                        _buildDownloadsTab(),
                        _buildPlaylistsTab(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadsTab() {
    if (_downloadedSongs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(CupertinoIcons.arrow_down_circle, size: 54, color: Colors.white24),
              ),
              const SizedBox(height: 16),
              const Text(
                'ยังไม่มีเพลงที่ดาวน์โหลดไว้',
                style: TextStyle(fontSize: 18, color: Colors.white70, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'แตะปุ่มดาวน์โหลดในหน้าเล่นเพลงเพื่อฟังเพลงแบบออฟไลน์โดยไม่ต้องใช้อินเทอร์เน็ต',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.white38, height: 1.4),
              ),
              const SizedBox(height: 120),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 160),
      itemCount: _downloadedSongs.length,
      itemBuilder: (context, index) {
        final song = _downloadedSongs[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: AppTheme.surface.withOpacity(0.65),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: song.thumbnailUrl,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  width: 48,
                  height: 48,
                  color: AppTheme.surfaceLight,
                  child: const Icon(CupertinoIcons.music_note, color: Colors.white30),
                ),
              ),
            ),
            title: Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
            ),
            subtitle: Row(
              children: [
                const Icon(CupertinoIcons.checkmark_circle_fill, color: AppTheme.secondary, size: 13),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(CupertinoIcons.trash, color: Colors.white38, size: 18),
              onPressed: () async {
                await _downloadService.removeDownloadedSong(song.id);
                _loadData();
              },
            ),
            onTap: () {
              _audioService.playPlaylist(_downloadedSongs, initialIndex: index);
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                backgroundColor: Colors.transparent,
                builder: (ctx) => NowPlayingSheet(song: song),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildPlaylistsTab() {
    if (_playlists.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(CupertinoIcons.music_albums, size: 54, color: Colors.white24),
              ),
              const SizedBox(height: 16),
              const Text(
                'ยังไม่มีเพลย์ลิสต์',
                style: TextStyle(fontSize: 18, color: Colors.white70, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'สร้างเพลย์ลิสต์ใหม่ หรือนำเข้าเพลย์ลิสต์จาก YouTube ได้ทันที',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.white38),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                icon: const Icon(CupertinoIcons.link, size: 16),
                label: const Text('นำเข้าเพลย์ลิสต์จาก YouTube'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: () => _showImportYouTubePlaylistDialog(),
              ),
              const SizedBox(height: 120),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 160),
      itemCount: _playlists.length,
      itemBuilder: (context, index) {
        final playlist = _playlists[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: AppTheme.surface.withOpacity(0.65),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: playlist.thumbnailUrl != null && playlist.thumbnailUrl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: playlist.thumbnailUrl!,
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 52,
                      height: 52,
                      decoration: const BoxDecoration(
                        gradient: AppTheme.cyanGradient,
                      ),
                      child: const Icon(CupertinoIcons.music_albums_fill, color: Colors.white, size: 24),
                    ),
            ),
            title: Text(
              playlist.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 15),
            ),
            subtitle: Text(
              '${playlist.songs.length} เพลง • ${playlist.isImportedFromYouTube ? "YouTube Music" : "เพลย์ลิสต์ส่วนตัว"}',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            trailing: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(CupertinoIcons.play_fill, color: Colors.white, size: 14),
            ),
            onTap: () {
              if (playlist.songs.isNotEmpty) {
                _audioService.playPlaylist(playlist.songs);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  backgroundColor: Colors.transparent,
                  builder: (ctx) => NowPlayingSheet(song: playlist.songs[0]),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('เพลย์ลิสต์นี้ยังไม่มีเพลง')),
                );
              }
            },
            onLongPress: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AppTheme.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  title: const Text('ลบเพลย์ลิสต์นี้?'),
                  content: Text('คุณต้องการลบ "${playlist.title}" ออกจากคลังเพลงใช่หรือไม่?'),
                  actions: [
                    TextButton(child: const Text('ยกเลิก'), onPressed: () => Navigator.pop(ctx, false)),
                    TextButton(child: const Text('ลบ', style: TextStyle(color: Colors.redAccent)), onPressed: () => Navigator.pop(ctx, true)),
                  ],
                ),
              );
              if (confirm == true) {
                await _playlistService.deletePlaylist(playlist.id);
                _loadData();
              }
            },
          ),
        );
      },
    );
  }

  void _showPlaylistActionMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.plus_square_fill, color: AppTheme.primaryLight, size: 24),
              title: const Text('สร้างเพลย์ลิสต์ใหม่', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _showCreatePlaylistDialog();
              },
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.link, color: AppTheme.secondary, size: 24),
              title: const Text('นำเข้าเพลย์ลิสต์จาก YouTube Music', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _showImportYouTubePlaylistDialog();
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showCreatePlaylistDialog() {
    final titleController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('สร้างเพลย์ลิสต์ใหม่', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: titleController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'ชื่อเพลย์ลิสต์...',
            hintStyle: TextStyle(color: AppTheme.textMuted),
          ),
        ),
        actions: [
          TextButton(child: const Text('ยกเลิก'), onPressed: () => Navigator.pop(ctx)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('สร้าง'),
            onPressed: () async {
              final title = titleController.text.trim();
              if (title.isNotEmpty) {
                Navigator.pop(ctx);
                await _playlistService.createPlaylist(title);
                _loadData();
              }
            },
          ),
        ],
      ),
    );
  }

  void _showImportYouTubePlaylistDialog() {
    final urlController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('นำเข้าเพลย์ลิสต์จาก YouTube', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: urlController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'วางลิงก์ https://music.youtube.com/playlist?list=...',
            hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 13),
          ),
        ),
        actions: [
          TextButton(child: const Text('ยกเลิก'), onPressed: () => Navigator.pop(ctx)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('นำเข้า'),
            onPressed: () async {
              final url = urlController.text.trim();
              if (url.isNotEmpty) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('กำลังนำเข้าเพลย์ลิสต์จาก YouTube...')),
                );
                final playlist = await _playlistService.importYouTubePlaylist(url);
                if (mounted) {
                  if (playlist != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('นำเข้า "${playlist.title}" สำเร็จ (${playlist.songs.length} เพลง)')),
                    );
                    _loadData();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('ไม่สามารถดึงข้อมูลเพลย์ลิสต์ได้ กรุณาตรวจสอบลิงก์อีกครั้ง')),
                    );
                  }
                }
              }
            },
          ),
        ],
      ),
    );
  }
}
