import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';

abstract class LastPlaybackStore {
  Future<Song?> load();

  Future<void> save(Song song);

  Future<void> clear();
}

class SharedPreferencesLastPlaybackStore implements LastPlaybackStore {
  static const key = 'music.lastPlayback.v1';

  @override
  Future<Song?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return _songFromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(Song song) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(key, jsonEncode(_songToJson(song)));
  }

  @override
  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(key);
  }
}

Map<String, dynamic> _songToJson(Song song) => {
      'id': song.id,
      'name': song.name,
      'source': song.source,
      'durationMs': song.durationMs,
      'libraryId': song.libraryId,
      'playedAt': song.playedAt?.toIso8601String(),
      'availableQualities': song.availableQualities,
      'artists': [
        for (final artist in song.artists)
          {
            'id': artist.id,
            'sourceId': artist.sourceId,
            'name': artist.name,
            'picUrl': artist.picUrl,
          },
      ],
      'album': {
        'id': song.album.id,
        'sourceId': song.album.sourceId,
        'name': song.album.name,
        'picUrl': song.album.picUrl,
      },
    };

Song? _songFromJson(Map<String, dynamic> json) {
  final id = _text(json['id']);
  final name = _text(json['name']);
  final source = _text(json['source']);
  if (id == null || name == null || source == null) return null;

  final artists = <Artist>[];
  final artistValues = json['artists'];
  if (artistValues is List) {
    for (final value in artistValues) {
      if (value is! Map) continue;
      final artist = Map<String, dynamic>.from(value);
      final artistName = _text(artist['name']);
      if (artistName == null) continue;
      artists.add(
        Artist(
          id: _int(artist['id']),
          sourceId: _text(artist['sourceId']),
          name: artistName,
          picUrl: _text(artist['picUrl']),
        ),
      );
    }
  }

  final albumValue = json['album'];
  final album = albumValue is Map
      ? Map<String, dynamic>.from(albumValue)
      : const <String, dynamic>{};
  final qualities = json['availableQualities'];
  return Song(
    id: id,
    name: name,
    source: source,
    artists: artists.isEmpty
        ? const [Artist(id: 0, name: '未知歌手')]
        : List.unmodifiable(artists),
    album: Album(
      id: _int(album['id']),
      sourceId: _text(album['sourceId']),
      name: _text(album['name']) ?? '',
      picUrl: _text(album['picUrl']),
    ),
    durationMs: _int(json['durationMs']).clamp(0, 1 << 53),
    libraryId: _text(json['libraryId']),
    playedAt: DateTime.tryParse(_text(json['playedAt']) ?? ''),
    availableQualities: qualities is List
        ? qualities.map(_text).whereType<String>().toList(growable: false)
        : const [],
  );
}

String? _text(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

int _int(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
