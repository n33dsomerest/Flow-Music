import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../data/models/song_model.dart';
import '../../data/sources/innertube_api_client.dart';
import '../../services/audio_player_service.dart';
import '../../services/download_cache_service.dart';
import '../../services/local_playlist_service.dart';
import '../theme/app_theme.dart';
import '../widgets/now_playing_sheet.dart';

/// Instant YouTube Music Search View with song action sheets.
class SearchView extends StatefulWidget {
  const SearchView({super.key});

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  final TextEditingController _searchController = TextEditingController();
  final InnerTubeApiClient _apiClient = InnerTubeApiClient();
  final AudioPlayerService _audioService = AudioPlayerService();
  final DownloadCacheService _downloadService = DownloadCacheService();
  final LocalPlaylistService _playlistService = LocalPlaylistService();

  Timer? _debounceTimer;
  List<SongModel> _searchResults = [];
  bool _isSearching = false;

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      setState(() => _isSearching = true);
      final results = await _apiClient.search(query.trim());
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Search Input Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    const Icon(CupertinoIcons.search, color: Colors.white54),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: 'ค้นหาเพลง, ศิลปิน, อัลบั้ม...',
                          hintStyle: TextStyle(color: Colors.white38),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(CupertinoIcons.clear_circled_solid, color: Colors.white54, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      ),
                  ],
                ),
              ),
            ),

            // Search State / Results List
            Expanded(
              child: _isSearching
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                  : _searchResults.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(CupertinoIcons.music_note_list, size: 64, color: Colors.white24),
                              SizedBox(height: 12),
                              Text(
                                'ค้นหาเพลงโปรดจาก YouTube Music',
                                style: TextStyle(color: Colors.white54, fontSize: 16),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final song = _searchResults[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: AppTheme.glassDecoration(),
                              child: ListTile(
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: CachedNetworkImage(
                                    imageUrl: song.thumbnailUrl,
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                title: Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  song.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(CupertinoIcons.ellipsis_vertical, color: Colors.white54),
                                  onPressed: () => _showSongOptionsSheet(song),
                                ),
                                onTap: () {
                                  _audioService.playPlaylist(_searchResults, initialIndex: index);
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
                        ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  void _showSongOptionsSheet(SongModel song) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedNetworkImage(imageUrl: song.thumbnailUrl, width: 40, height: 40, fit: BoxFit.cover),
              ),
              title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54)),
            ),
            const Divider(color: Colors.white12),
            ListTile(
              leading: const Icon(CupertinoIcons.play_arrow_solid, color: AppTheme.primary),
              title: const Text('เล่นทันที', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _audioService.playSong(song);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  backgroundColor: Colors.transparent,
                  builder: (c) => NowPlayingSheet(song: song),
                );
              },
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.text_badge_plus, color: Colors.white70),
              title: const Text('เพิ่มเข้าคิว', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _audioService.addToQueue(song);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เพิ่ม "${song.title}" เข้าคิวแล้ว')));
              },
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.music_albums, color: AppTheme.secondary),
              title: const Text('เพิ่มเข้าเพลย์ลิสต์...', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _showAddToPlaylistDialog(song);
              },
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.arrow_down_circle, color: Colors.white70),
              title: const Text('ดาวน์โหลดไว้ฟังออฟไลน์', style: TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กำลังดาวน์โหลด...')));
                final ok = await _downloadService.downloadSong(song);
                if (mounted && ok) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ดาวน์โหลด "${song.title}" เสร็จแล้ว')));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAddToPlaylistDialog(SongModel song) async {
    final playlists = await _playlistService.getPlaylists();
    if (!mounted) return;

    if (playlists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('คุณยังไม่มีเพลย์ลิสต์ กรุณาสร้างเพลย์ลิสต์ในหน้าคลังเพลงก่อน')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('เลือกเพลย์ลิสต์', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: playlists.length,
            itemBuilder: (c, i) {
              final p = playlists[i];
              return ListTile(
                title: Text(p.title, style: const TextStyle(color: Colors.white)),
                subtitle: Text('${p.songs.length} เพลง', style: const TextStyle(color: Colors.white54)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await _playlistService.addSongToPlaylist(p.id, song);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(ok ? 'เพิ่มลงใน "${p.title}" แล้ว' : 'เพลงนี้อยู่ในเพลย์ลิสต์แล้ว')),
                    );
                  }
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
