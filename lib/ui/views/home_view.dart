import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../data/models/song_model.dart';
import '../../data/sources/innertube_api_client.dart';
import '../../services/audio_player_service.dart';
import '../theme/app_theme.dart';
import '../widgets/now_playing_sheet.dart';

/// Ultra-Modern Cyber-Glass Home View with Horizontal Carousels, Top Charts & Shimmer States.
class HomeView extends StatefulWidget {
  final VoidCallback onSearchTapped;

  const HomeView({super.key, required this.onSearchTapped});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  final InnerTubeApiClient _apiClient = InnerTubeApiClient();
  final AudioPlayerService _audioService = AudioPlayerService();

  final List<String> _moods = [
    'Top Charts',
    'เพลงไทยฮิต',
    'Relax & Chill',
    'T-POP',
    'Focus & Lo-Fi',
    'Workout',
    'เพลงเศร้า',
    'Rock & Indie',
  ];
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

    final query = mood == 'Top Charts' ? 'Top Hits Thailand' : '$mood music';
    final songs = await _apiClient.search(query);

    if (mounted) {
      setState(() {
        _songs = songs;
        _isLoading = false;
      });
    }
  }

  String _getTimeGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'สวัสดีตอนเช้า';
    if (hour < 17) return 'สวัสดีตอนบ่าย';
    if (hour < 20) return 'สวัสดีตอนเย็น';
    return 'ยินดีต้อนรับยามค่ำ';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppTheme.primaryLight,
          backgroundColor: AppTheme.surfaceLight,
          onRefresh: () => _loadMoodContent(_selectedMood),
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Top Sleek Header with Greeting & Search Action
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getTimeGreeting(),
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              ShaderMask(
                                shaderCallback: (bounds) => AppTheme.primaryGradient.createShader(bounds),
                                child: const Text(
                                  'Flow Music',
                                  style: TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppTheme.primary.withOpacity(0.4), width: 1),
                                ),
                                child: const Text(
                                  'PRO',
                                  style: TextStyle(
                                    color: AppTheme.primaryLight,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: widget.onSearchTapped,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: AppTheme.glassDecoration(
                            borderRadius: 14,
                            color: Colors.white.withOpacity(0.06),
                            borderColor: Colors.white.withOpacity(0.12),
                          ),
                          child: const Icon(CupertinoIcons.search, color: Colors.white, size: 22),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Premium Ad-Free Glassmorphic Banner
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF261245), Color(0xFF16152E), Color(0xFF0F172A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: AppTheme.primary.withOpacity(0.35), width: 1.2),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primary.withOpacity(0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.accentPink.withOpacity(0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(CupertinoIcons.shield_lefthalf_fill, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: const [
                                Text(
                                  'ฟังเพลงไร้โฆษณา 100%',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                ),
                                SizedBox(width: 6),
                                Icon(CupertinoIcons.checkmark_seal_fill, color: AppTheme.secondary, size: 16),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'สตรีมเสียง Hi-Res คมชัดสูงจาก YouTube Music พร้อมเนื้อเพลงซิงค์สด',
                              style: TextStyle(color: Color(0xFFB0B7C3), fontSize: 12, height: 1.3),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Modern Pill Chips (Horizontal Moods)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 56,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    itemCount: _moods.length,
                    itemBuilder: (context, index) {
                      final mood = _moods[index];
                      final isSelected = mood == _selectedMood;

                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () {
                            if (!isSelected) _loadMoodContent(mood);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                            decoration: BoxDecoration(
                              gradient: isSelected ? AppTheme.primaryGradient : null,
                              color: isSelected ? null : AppTheme.surfaceLight.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: isSelected ? Colors.transparent : Colors.white.withOpacity(0.12),
                                width: 1,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: AppTheme.primary.withOpacity(0.35),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Center(
                              child: Text(
                                mood,
                                style: TextStyle(
                                  color: isSelected ? Colors.white : Colors.white70,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // Content or Shimmer Loading State
              if (_isLoading)
                SliverToBoxAdapter(child: _buildSkeletonLoading())
              else if (_songs.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyState(),
                )
              else ...[
                // Section 1: Featured Carousel (Large Artwork Horizontal Cards)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 4,
                              height: 18,
                              decoration: BoxDecoration(
                                gradient: AppTheme.primaryGradient,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'แนะนำสำหรับคุณ',
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${_songs.length} เพลง',
                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),

                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 200,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _songs.length > 8 ? 8 : _songs.length,
                      itemBuilder: (context, index) {
                        final song = _songs[index];
                        return _buildFeaturedCard(song, index);
                      },
                    ),
                  ),
                ),

                // Section 2: Top Charts Vertical Ranked List
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 4,
                              height: 18,
                              decoration: BoxDecoration(
                                gradient: AppTheme.cyanGradient,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _selectedMood,
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            backgroundColor: AppTheme.primary.withOpacity(0.12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          icon: const Icon(CupertinoIcons.play_fill, size: 14, color: AppTheme.primaryLight),
                          label: const Text(
                            'เล่นทั้งหมด',
                            style: TextStyle(color: AppTheme.primaryLight, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
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

                // Ranked List Tiles
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final song = _songs[index];
                        final rank = index + 1;
                        return _buildSongTile(song, rank, index);
                      },
                      childCount: _songs.length,
                    ),
                  ),
                ),
              ],

              // Safe Space for Floating MiniPlayer and Frosted Bottom Bar
              const SliverToBoxAdapter(child: SizedBox(height: 160)),
            ],
          ),
        ),
      ),
    );
  }

  /// Horizontal Big Featured Card with Floating Play Button
  Widget _buildFeaturedCard(SongModel song, int index) {
    return GestureDetector(
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
      child: Container(
        width: 140,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Artwork with Glow & Play Button
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: CachedNetworkImage(
                    imageUrl: song.thumbnailUrl,
                    width: 140,
                    height: 140,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      width: 140,
                      height: 140,
                      color: AppTheme.surfaceLight,
                    ),
                    errorWidget: (_, __, ___) => Container(
                      width: 140,
                      height: 140,
                      color: AppTheme.surfaceLight,
                      child: const Icon(CupertinoIcons.music_note, color: Colors.white30, size: 36),
                    ),
                  ),
                ),
                // Gradient Bottom Overlay
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: [Colors.transparent, Colors.black.withOpacity(0.5)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
                // Floating Glass Play Icon
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.4),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const Icon(CupertinoIcons.play_fill, color: Colors.white, size: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Modern Ranked Song Tile with Glassmorphic Card
  Widget _buildSongTile(SongModel song, int rank, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06), width: 1),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ranking Number Badge
            SizedBox(
              width: 24,
              child: Text(
                rank < 10 ? '0$rank' : '$rank',
                style: TextStyle(
                  color: rank <= 3 ? AppTheme.primaryLight : AppTheme.textMuted,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 8),
            // Thumbnail
            ClipRRect(
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
                  child: const Icon(CupertinoIcons.music_note, color: Colors.white24, size: 20),
                ),
              ),
            ),
          ],
        ),
        title: Text(
          song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          song.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            CupertinoIcons.play_fill,
            color: AppTheme.primaryLight,
            size: 14,
          ),
        ),
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
  }

  /// Shimmering Skeleton Placeholders while loading
  Widget _buildSkeletonLoading() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 140,
            height: 18,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: List.generate(
              3,
              (index) => Container(
                margin: const EdgeInsets.only(right: 12),
                width: 110,
                height: 150,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          ...List.generate(
            5,
            (index) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              height: 60,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.surfaceLight.withOpacity(0.5),
              shape: BoxShape.circle,
            ),
            child: const Icon(CupertinoIcons.waveform_path_badge_plus, size: 54, color: AppTheme.primaryLight),
          ),
          const SizedBox(height: 16),
          const Text(
            'กำลังเชื่อมต่อ YouTube Music...',
            style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'แตะปุ่มด้านล่างเพื่อลองโหลดใหม่อีกครั้ง',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            ),
            icon: const Icon(CupertinoIcons.refresh, size: 18),
            label: const Text('ลองใหม่อีกครั้ง', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () => _loadMoodContent(_selectedMood),
          ),
        ],
      ),
    );
  }
}
