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

/// Cyber-Glass YouTube Music Instant Search with Suggested Topics & Action Sheet.
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

  final List<String> _suggestedTags = [
    'เพลงฮิต TikTok',
    'Three Man Down',
    'Billkin & PP',
    'NONT TANONT',
    'Jeff Satur',
    'Taylor Swift',
    'T-POP Top 50',
    'Lo-Fi Study',
    'เพลงรักฟังสบาย',
    'Bowkylion',
  ];

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

    _debounceTimer = Timer(const Duration(milliseconds: 400), () async {
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

  void _searchTag(String tag) {
    _searchController.text = tag;
    _onSearchChanged(tag);
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
        bottom: false,
        child: Column(
          children: [
            // Modern Floating Search Input
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.12), width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(CupertinoIcons.search, color: AppTheme.primaryLight, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        decoration: const InputDecoration(
                          hintText: 'ค้นหาเพลง, ศิลปิน, อัลบั้ม...',
                          hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 14),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                    if (_searchController.text.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                        child: const Icon(CupertinoIcons.clear_circled_solid, color: AppTheme.textMuted, size: 20),
                      ),
                  ],
                ),
              ),
            ),

            // Content Area: Suggested Topics vs Search Results
            Expanded(
              child: _isSearching
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryLight))
                  : _searchResults.isEmpty
                      ? _buildInitialSuggestions()
                      : _buildSearchResultsList(),
            ),
          ],
        ),
      ),
    );
  }

  /// Initial Screen with Quick Search Tags & Trending Topics
  Widget _buildInitialSuggestions() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(CupertinoIcons.flame_fill, color: AppTheme.accentPink, size: 20),
              SizedBox(width: 8),
              Text(
                'ค้นหายอดนิยม',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 10,
            children: _suggestedTags.map((tag) {
              return GestureDetector(
                onTap: () => _searchTag(tag),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceLight.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(CupertinoIcons.search, size: 14, color: AppTheme.primaryLight),
                      const SizedBox(width: 6),
                      Text(
                        tag,
                        style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 36),
          Center(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceLight.withOpacity(0.35),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(CupertinoIcons.music_mic, size: 48, color: Colors.white24),
                ),
                const SizedBox(height: 14),
                const Text(
                  'ค้นหาเพลงโปรดจากศิลปินที่คุณชื่นชอบ',
                  style: TextStyle(color: Colors.white60, fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 160),
        ],
      ),
    );
  }

  /// Results List View
  Widget _buildSearchResultsList() {
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 160),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final song = _searchResults[index];
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
            subtitle: Text(
              song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(CupertinoIcons.ellipsis, color: Colors.white54, size: 20),
                  onPressed: () => _showSongOptionsSheet(song),
                ),
              ],
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
    );
  }

  void _showSongOptionsSheet(SongModel song) {
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
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(imageUrl: song.thumbnailUrl, width: 44, height: 44, fit: BoxFit.cover),
              ),
              title: Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 15),
              ),
              subtitle: Text(
                song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
            const Divider(color: Colors.white10),
            ListTile(
              leading: const Icon(CupertinoIcons.play_circle_fill, color: AppTheme.primaryLight, size: 24),
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
              leading: const Icon(CupertinoIcons.text_badge_plus, color: Colors.white70, size: 24),
              title: const Text('เพิ่มเข้าคิวเล่นต่อ', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _audioService.addToQueue(song);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เพิ่ม "${song.title}" เข้าคิวแล้ว')));
              },
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.music_albums, color: AppTheme.secondary, size: 24),
              title: const Text('เพิ่มเข้าเพลย์ลิสต์...', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _showAddToPlaylistDialog(song);
              },
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.arrow_down_circle, color: AppTheme.accentPink, size: 24),
              title: const Text('ดาวน์โหลดไว้ฟังออฟไลน์', style: TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เริ่มดาวน์โหลด "${song.title}"...')));
                final ok = await _downloadService.downloadSong(song);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(ok ? 'ดาวน์โหลด "${song.title}" เสร็จสมบูรณ์ 100%!' : 'ดาวน์โหลดไม่สำเร็จ กรุณาลองใหม่'),
                  ));
                }
              },
            ),
            const SizedBox(height: 12),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('เลือกเพลย์ลิสต์', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: playlists.length,
            itemBuilder: (c, i) {
              final p = playlists[i];
              return ListTile(
                leading: const Icon(CupertinoIcons.music_note_list, color: AppTheme.primaryLight),
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
