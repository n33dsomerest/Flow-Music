import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models/song_model.dart';
import '../data/sources/innertube_api_client.dart';

/// Represents a custom user playlist or imported YouTube playlist.
class LocalPlaylist {
  final String id;
  final String title;
  final String description;
  final String? thumbnailUrl;
  final List<SongModel> songs;
  final DateTime createdAt;
  final bool isImportedFromYouTube;

  const LocalPlaylist({
    required this.id,
    required this.title,
    this.description = '',
    this.thumbnailUrl,
    required this.songs,
    required this.createdAt,
    this.isImportedFromYouTube = false,
  });

  LocalPlaylist copyWith({
    String? id,
    String? title,
    String? description,
    String? thumbnailUrl,
    List<SongModel>? songs,
    DateTime? createdAt,
    bool? isImportedFromYouTube,
  }) {
    return LocalPlaylist(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      songs: songs ?? this.songs,
      createdAt: createdAt ?? this.createdAt,
      isImportedFromYouTube: isImportedFromYouTube ?? this.isImportedFromYouTube,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'thumbnailUrl': thumbnailUrl,
      'songs': songs.map((s) => s.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'isImportedFromYouTube': isImportedFromYouTube,
    };
  }

  factory LocalPlaylist.fromJson(Map<String, dynamic> json) {
    return LocalPlaylist(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      thumbnailUrl: json['thumbnailUrl'] as String?,
      songs: (json['songs'] as List<dynamic>?)
              ?.map((item) => SongModel.fromJson(item as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      isImportedFromYouTube: json['isImportedFromYouTube'] as bool? ?? false,
    );
  }
}

/// Service managing user playlists and YouTube playlist imports.
class LocalPlaylistService {
  static const String _playlistsKey = 'user_local_playlists';
  final InnerTubeApiClient _apiClient = InnerTubeApiClient();

  /// Retrieve all user playlists.
  Future<List<LocalPlaylist>> getPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_playlistsKey) ?? [];
    return list.map((item) => LocalPlaylist.fromJson(jsonDecode(item) as Map<String, dynamic>)).toList();
  }

  /// Create a new local playlist.
  Future<LocalPlaylist> createPlaylist(String title, {String description = ''}) async {
    final id = 'local_${DateTime.now().millisecondsSinceEpoch}';
    final playlist = LocalPlaylist(
      id: id,
      title: title,
      description: description,
      songs: [],
      createdAt: DateTime.now(),
    );

    await _savePlaylist(playlist);
    return playlist;
  }

  /// Add a song to a playlist.
  Future<bool> addSongToPlaylist(String playlistId, SongModel song) async {
    final playlists = await getPlaylists();
    final index = playlists.indexWhere((p) => p.id == playlistId);
    if (index == -1) return false;

    final playlist = playlists[index];
    if (playlist.songs.any((s) => s.id == song.id)) {
      return false; // Already in playlist
    }

    final updatedSongs = List<SongModel>.from(playlist.songs)..add(song);
    final updatedPlaylist = playlist.copyWith(
      songs: updatedSongs,
      thumbnailUrl: playlist.thumbnailUrl ?? song.thumbnailUrl,
    );

    playlists[index] = updatedPlaylist;
    await _saveAllPlaylists(playlists);
    return true;
  }

  /// Remove a song from a playlist.
  Future<bool> removeSongFromPlaylist(String playlistId, String songId) async {
    final playlists = await getPlaylists();
    final index = playlists.indexWhere((p) => p.id == playlistId);
    if (index == -1) return false;

    final playlist = playlists[index];
    final updatedSongs = List<SongModel>.from(playlist.songs)..removeWhere((s) => s.id == songId);
    final updatedPlaylist = playlist.copyWith(songs: updatedSongs);

    playlists[index] = updatedPlaylist;
    await _saveAllPlaylists(playlists);
    return true;
  }

  /// Delete a playlist.
  Future<void> deletePlaylist(String playlistId) async {
    final playlists = await getPlaylists();
    playlists.removeWhere((p) => p.id == playlistId);
    await _saveAllPlaylists(playlists);
  }

  /// Import a public YouTube or YouTube Music playlist by URL or ID.
  Future<LocalPlaylist?> importYouTubePlaylist(String urlOrId) async {
    final playlistId = _extractPlaylistId(urlOrId);
    if (playlistId == null || playlistId.isEmpty) return null;

    try {
      final songs = await _apiClient.getPlaylistSongs(playlistId);
      if (songs.isEmpty) return null;

      final playlist = LocalPlaylist(
        id: 'yt_$playlistId',
        title: 'YouTube Playlist ($playlistId)',
        description: 'Imported from YouTube Music',
        thumbnailUrl: songs.first.thumbnailUrl,
        songs: songs,
        createdAt: DateTime.now(),
        isImportedFromYouTube: true,
      );

      await _savePlaylist(playlist);
      return playlist;
    } catch (e) {
      debugPrint('[LocalPlaylistService] Error importing playlist: $e');
      return null;
    }
  }

  String? _extractPlaylistId(String input) {
    final trimmed = input.trim();
    if (trimmed.contains('list=')) {
      final match = RegExp(r'[?&]list=([a-zA-Z0-9_-]+)').firstMatch(trimmed);
      if (match != null) return match.group(1);
      final uri = Uri.tryParse(trimmed);
      return uri?.queryParameters['list'];
    }
    return trimmed;
  }

  Future<void> _savePlaylist(LocalPlaylist playlist) async {
    final playlists = await getPlaylists();
    playlists.removeWhere((p) => p.id == playlist.id);
    playlists.insert(0, playlist);
    await _saveAllPlaylists(playlists);
  }

  Future<void> _saveAllPlaylists(List<LocalPlaylist> playlists) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = playlists.map((p) => jsonEncode(p.toJson())).toList();
    await prefs.setStringList(_playlistsKey, jsonList);
  }
}
