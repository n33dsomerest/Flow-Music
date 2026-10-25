import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../data/models/song_model.dart';
import '../../services/audio_player_service.dart';
import '../../services/download_cache_service.dart';
import '../../services/local_playlist_service.dart';
import '../theme/app_theme.dart';

/// Enhanced Library View with Offline Downloads and Custom/Imported Playlists.
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
      appBar: AppBar(
        title: const Text('คลังเพลง'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primary,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: 'ดาวน์โหลดแล้ว (Offline)'),
            Tab(text: 'เพลย์ลิสต์ของฉัน'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.plus_circle, color: Colors.white),
            tooltip: 'สร้างหรือนำเข้าเพลย์ลิสต์',
            onPressed: () => _showPlaylistActionMenu(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildDownloadsTab(),
                _buildPlaylistsTab(),
              ],
            ),
    );
  }

  Widget _buildDownloadsTab() {
    if (_downloadedSongs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(CupertinoIcons.arrow_down_circle, size: 72, color: Colors.white24),
            SizedBox(height: 16),
            Text(
              'ยังไม่มีเพลงที่ดาวน์โหลดไว้',
              style: TextStyle(fontSize: 18, color: Colors.white70, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'แตะปุ่มดาวน์โหลดในหน้าเล่นเพลงเพื่อฟังแบบออฟไลน์',
              style: TextStyle(fontSize: 14, color: Colors.white38),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _downloadedSongs.length,
      itemBuilder: (context, index) {
        final song = _downloadedSongs[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: AppTheme.glassDecoration(),
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: song.thumbnailUrl,
                width: 50,
                height: 50,
                fit: BoxFit.cover,
              ),
            ),
            title: Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            subtitle: Row(
              children: [
                const Icon(CupertinoIcons.check_mark_circled_fill, color: AppTheme.secondary, size: 14),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(CupertinoIcons.trash, color: Colors.white38, size: 20),
              onPressed: () async {
                await _downloadService.removeDownloadedSong(song.id);
                _loadData();
              },
            ),
            onTap: () {
              _audioService.playPlaylist(_downloadedSongs, initialIndex: index);
            },
          ),
        );
      },
    );
  }

  Widget _buildPlaylistsTab() {
    if (_playlists.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(CupertinoIcons.music_albums, size: 72, color: Colors.white24),
            const SizedBox(height: 16),
            const Text(
              'ยังไม่มีเพลย์ลิสต์',
              style: TextStyle(fontSize: 18, color: Colors.white70, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(CupertinoIcons.link),
              label: const Text('นำเข้าเพลย์ลิสต์จาก YouTube'),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              onPressed: () => _showImportYouTubePlaylistDialog(),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _playlists.length,
      itemBuilder: (context, index) {
        final playlist = _playlists[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: AppTheme.glassDecoration(),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: playlist.thumbnailUrl != null && playlist.thumbnailUrl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: playlist.thumbnailUrl!,
                      width: 54,
                      height: 54,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 54,
                      height: 54,
                      color: AppTheme.surfaceLight,
                      child: const Icon(CupertinoIcons.music_albums_fill, color: Colors.white38),
                    ),
            ),
            title: Text(
              playlist.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
            ),
            subtitle: Text(
              '${playlist.songs.length} เพลง • ${playlist.isImportedFromYouTube ? "YouTube Music" : "เพลย์ลิสต์ส่วนตัว"}',
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
            trailing: IconButton(
              icon: const Icon(CupertinoIcons.play_circle_fill, color: AppTheme.primary, size: 36),
              onPressed: () {
                if (playlist.songs.isNotEmpty) {
                  _audioService.playPlaylist(playlist.songs);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('เพลย์ลิสต์นี้ยังไม่มีเพลง')),
                  );
                }
              },
            ),
            onLongPress: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AppTheme.surface,
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(CupertinoIcons.plus_square_fill, color: AppTheme.primary),
              title: const Text('สร้างเพลย์ลิสต์ใหม่', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _showCreatePlaylistDialog();
              },
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.link, color: AppTheme.secondary),
              title: const Text('นำเข้าเพลย์ลิสต์จาก YouTube Music', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _showImportYouTubePlaylistDialog();
              },
            ),
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
        title: const Text('สร้างเพลย์ลิสต์ใหม่', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: titleController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'ชื่อเพลย์ลิสต์...',
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(child: const Text('ยกเลิก'), onPressed: () => Navigator.pop(ctx)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
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
        title: const Text('นำเข้าเพลย์ลิสต์จาก YouTube', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: urlController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'วางลิงก์ เช่น https://music.youtube.com/playlist?list=...',
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(child: const Text('ยกเลิก'), onPressed: () => Navigator.pop(ctx)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
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
