import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../data/models/song_model.dart';
import '../../data/sources/innertube_api_client.dart';
import '../../services/audio_player_service.dart';
import '../../services/playback_history_service.dart';
import '../theme/app_theme.dart';
import '../widgets/now_playing_sheet.dart';

/// Ultra-Modern Cyber-Glass Home View featuring:
/// 1. "เพลงที่คุณอาจจะชอบ" (Smart personalized recommendations based on listening tastes)
/// 2. "เพลงที่คุณฟังบ่อย" (Frequently listened tracks with play count badges)
/// 3. Mood Categories & Top Charts Ranking
class HomeView extends StatefulWidget {
  final VoidCallback onSearchTapped;

  const HomeView({super.key, required this.onSearchTapped});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  final InnerTubeApiClient _apiClient = InnerTubeApiClient();
  final AudioPlayerService _audioService = AudioPlayerService();
  final PlaybackHistoryService _historyService = PlaybackHistoryService();

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

  List<SongModel> _recommendedSongs = [];
  List<MapEntry<SongModel, int>> _mostPlayedSongs = [];
  List<SongModel> _moodSongs = [];

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAllHomeData();
  }

  Future<void> _loadAllHomeData() async {
    setState(() => _isLoading = true);

    await Future.wait([
      _loadRecommendationsAndHistory(),
      _loadMoodContent(_selectedMood, updateState: false),
    ]);

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadRecommendationsAndHistory() async {
    final mostPlayed = await _historyService.getMostPlayedSongs(limit: 10);
    final recommended = await _historyService.getRecommendedSongs(limit: 10);

    if (mounted) {
      setState(() {
        _mostPlayedSongs = mostPlayed;
        _recommendedSongs = recommended;
      });
    }
  }

  Future<void> _loadMoodContent(String mood, {bool updateState = true}) async {
    if (updateState) {
      setState(() {
        _selectedMood = mood;
        _isLoading = true;
      });
    }

    final query = mood == 'Top Charts' ? 'Top Hits Thailand' : '$mood music';
    final songs = await _apiClient.search(query);

    if (mounted) {
      setState(() {
        _selectedMood = mood;
        _moodSongs = songs;
        if (updateState) _isLoading = false;
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
          onRefresh: _loadAllHomeData,
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
                              'สตรีมเสียง Hi-Res คมชัดสูง 320kbps พร้อมเนื้อเพลงซิงค์สด',
                              style: TextStyle(color: Color(0xFFB0B7C3), fontSize: 12, height: 1.3),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (_isLoading)
                SliverToBoxAdapter(child: _buildSkeletonLoading())
              else ...[
                // ==========================================
                // Section 1: "เพลงที่คุณอาจจะชอบ" (Recommended For You)
                // ==========================================
                if (_recommendedSongs.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
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
                              const Text(
                                'เพลงที่คุณอาจจะชอบ',
                                style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(CupertinoIcons.sparkles, color: AppTheme.primaryLight, size: 12),
                                SizedBox(width: 4),
                                Text(
                                  'คัดสรรเพื่อคุณ',
                                  style: TextStyle(color: AppTheme.primaryLight, fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 204,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _recommendedSongs.length,
                        itemBuilder: (context, index) {
                          final song = _recommendedSongs[index];
                          return _buildSongCard(song, index, _recommendedSongs);
                        },
                      ),
                    ),
                  ),
                ],

                // ==========================================
                // Section 2: "เพลงที่คุณฟังบ่อย" (Frequently Listened)
                // ==========================================
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 4,
                              height: 18,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFFF5252), Color(0xFFFF7A00)],
                                ),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'เพลงที่คุณฟังบ่อย',
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        if (_mostPlayedSongs.isNotEmpty)
                          Text(
                            'ฟังซ้ำบ่อยสุด',
                            style: TextStyle(color: AppTheme.accentPink.withOpacity(0.9), fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                      ],
                    ),
                  ),
                ),

                if (_mostPlayedSongs.isNotEmpty)
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 204,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _mostPlayedSongs.length,
                        itemBuilder: (context, index) {
                          final entry = _mostPlayedSongs[index];
                          final playlist = _mostPlayedSongs.map((e) => e.key).toList();
                          return _buildMostPlayedCard(entry.key, entry.value, index, playlist);
                        },
                      ),
                    ),
                  )
                else
                  SliverToBoxAdapter(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceLight.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.accentPink.withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(CupertinoIcons.flame, color: AppTheme.accentPink, size: 20),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'เมื่อคุณเริ่มฟังเพลง เพลงที่คุณกดฟังบ่อยที่สุดจะปรากฏที่นี่โดยอัตโนมัติ',
                              style: TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // ==========================================
                // Section 3: Moods & Categories (Chips)
                // ==========================================
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                    child: Row(
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
                        const Text(
                          'สำรวจตามแนวเพลง',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 54,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
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

                // ==========================================
                // Section 4: Ranked List for Selected Mood
                // ==========================================
                if (_moodSongs.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _selectedMood,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
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
                              _audioService.playPlaylist(_moodSongs);
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                useSafeArea: true,
                                backgroundColor: Colors.transparent,
                                builder: (ctx) => NowPlayingSheet(song: _moodSongs[0]),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final song = _moodSongs[index];
                          final rank = index + 1;
                          return _buildSongTile(song, rank, index, _moodSongs);
                        },
                        childCount: _moodSongs.length,
                      ),
                    ),
                  ),
                ],
              ],

              // Safe Space for Floating MiniPlayer and Frosted Bottom Bar
              const SliverToBoxAdapter(child: SizedBox(height: 160)),
            ],
          ),
        ),
      ),
    );
  }

  /// Horizontal Featured Card for "เพลงที่คุณอาจจะชอบ"
  Widget _buildSongCard(SongModel song, int index, List<SongModel> playlist) {
    return GestureDetector(
      onTap: () {
        _audioService.playPlaylist(playlist, initialIndex: index);
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
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: [Colors.transparent, Colors.black.withOpacity(0.55)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
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

  /// Horizontal Card for "เพลงที่คุณฟังบ่อย" with play count badge
  Widget _buildMostPlayedCard(SongModel song, int playCount, int index, List<SongModel> playlist) {
    return GestureDetector(
      onTap: () {
        _audioService.playPlaylist(playlist, initialIndex: index);
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
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: [Colors.transparent, Colors.black.withOpacity(0.65)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
                // Play count badge
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.accentPink.withOpacity(0.6), width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(CupertinoIcons.flame_fill, color: AppTheme.accentPink, size: 11),
                        const SizedBox(width: 3),
                        Text(
                          '$playCount ครั้ง',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Play Button
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
  Widget _buildSongTile(SongModel song, int rank, int index, List<SongModel> playlist) {
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
          _audioService.playPlaylist(playlist, initialIndex: index);
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
            width: 160,
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
}
