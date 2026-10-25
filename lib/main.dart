import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/audio_player_service.dart';
import 'ui/theme/app_theme.dart';
import 'ui/views/home_view.dart';
import 'ui/views/library_view.dart';
import 'ui/views/search_view.dart';
import 'ui/widgets/mini_player.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set system UI style (transparent status bar & navigation)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppTheme.surface,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Initialize background audio engine
  await AudioPlayerService().init();

  runApp(const FlowMusicApp());
}

class FlowMusicApp extends StatelessWidget {
  const FlowMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flow Music',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const MainNavigationScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeView(onSearchTapped: () => setState(() => _currentIndex = 1)),
      const SearchView(),
      const LibraryView(),
    ];

    return Scaffold(
      body: Stack(
        children: [
          // Current Page
          IndexedStack(
            index: _currentIndex,
            children: pages,
          ),

          // Docked Mini-Player above Bottom Navigation
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: MiniPlayer(),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.house_fill),
            label: 'หน้าแรก',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.search),
            label: 'ค้นหา',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.music_albums_fill),
            label: 'คลังเพลง',
          ),
        ],
      ),
    );
  }
}
