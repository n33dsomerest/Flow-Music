import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../data/models/song_model.dart';
import '../../data/sources/innertube_api_client.dart';
import '../../services/audio_player_service.dart';
import '../theme/app_theme.dart';
import '../widgets/now_playing_sheet.dart';

/// Dynamic Home view with mood chips, trending charts, and recommendations.
class HomeView extends StatefulWidget {
  final VoidCallback onSearchTapped;

  const HomeView({super.key, required this.onSearchTapped});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  final InnerTubeApiClient _apiClient = InnerTubeApiClient();
  final AudioPlayerService _audioService = AudioPlayerService();

  final List<String> _moods = ['Top Charts', 'เพลงไทยฮิต', 'Relax & Chill', 'Focus & Lo-Fi', 'Workout', 'Party'];
  String _selectedMood = 'Top Charts';

  List<SongModel> _songs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMoodContent(_selectedMood);
  }

  Future<void> _loadMoodContent(String mood) async {
    setState(() {
      _selectedMood = mood;
      _isLoading = true;
    });

    final query = mood == 'Top Charts' ? 'Top Hits 2024' : '$mood music';
    final songs = await _apiClient.search(query);

    if (mounted) {
      setState(() {
        _songs = songs;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.primary,
          onRefresh: () => _loadMoodContent(_selectedMood),
          child: CustomScrollView(
            slivers: [
              // App Bar with Logo & Search Shortcut
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [AppTheme.primary, AppTheme.secondary],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(CupertinoIcons.waveform, color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Flow Music',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(CupertinoIcons.search, color: Colors.white, size: 26),
                        onPressed: widget.onSearchTapped,
                      ),
                    ],
                  ),
                ),
              ),

              // Ad-Free Badge Banner
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  padding: const EdgeInsets.all(16),
                  decoration: AppTheme.glassDecoration(
                    color: AppTheme.primary.withOpacity(0.15),
                    borderColor: AppTheme.primary.withOpacity(0.3),
                  ),
                  child: Row(
                    children: [
                      const Icon(CupertinoIcons.shield_fill, color: AppTheme.secondary, size: 28),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'ฟังเพลงไม่มีโฆษณา 100%',
                              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'สตรีมเสียงความคมชัดสูงจาก YouTube Music พร้อมเนื้อเพลงซิงค์สด',
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Mood & Genre Horizontal Chips
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 52,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _moods.length,
                    itemBuilder: (context, index) {
                      final mood = _moods[index];
                      final isSelected = mood == _selectedMood;

                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          selected: isSelected,
                          label: Text(mood),
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : Colors.white70,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          backgroundColor: AppTheme.surfaceLight,
                          selectedColor: AppTheme.primary,
                          checkmarkColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: isSelected ? AppTheme.primary : Colors.white12,
                            ),
                          ),
                          onSelected: (val) {
                            if (val) _loadMoodContent(mood);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ),

              // Section Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _selectedMood,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      if (_songs.isNotEmpty)
                        TextButton.icon(
                          icon: const Icon(CupertinoIcons.play_fill, size: 16, color: AppTheme.secondary),
                          label: const Text('เล่นทั้งหมด', style: TextStyle(color: AppTheme.secondary)),
                          onPressed: () {
                            _audioService.playPlaylist(_songs);
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              useSafeArea: true,
                              backgroundColor: Colors.transparent,
                              builder: (ctx) => NowPlayingSheet(song: _songs[0]),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),

              // Song List or Loading / Empty State
              if (_isLoading)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                )
              else if (_songs.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(CupertinoIcons.music_note_list, size: 54, color: Colors.white24),
                        const SizedBox(height: 12),
                        const Text('กำลังเชื่อมต่อ YouTube Music...', style: TextStyle(color: Colors.white54)),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                          icon: const Icon(CupertinoIcons.refresh),
                          label: const Text('ลองโหลดอีกครั้ง'),
                          onPressed: () => _loadMoodContent(_selectedMood),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final song = _songs[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: AppTheme.glassDecoration(),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(
                                imageUrl: song.thumbnailUrl,
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(
                                  width: 50,
                                  height: 50,
                                  color: AppTheme.surfaceLight,
                                  child: const Icon(CupertinoIcons.music_note, color: Colors.white38),
                                ),
                              ),
                            ),
                            title: Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
                            ),
                            subtitle: Text(
                              song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white60, fontSize: 13),
                            ),
                            trailing: const Icon(CupertinoIcons.play_circle_fill, color: AppTheme.primary, size: 32),
                            onTap: () {
                              _audioService.playPlaylist(_songs, initialIndex: index);
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
                      childCount: _songs.length,
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      ),
    );
  }
}
