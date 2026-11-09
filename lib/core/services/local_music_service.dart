import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/song.dart';
import '../models/playback_info.dart';
import 'song_download_service.dart';

class LocalMusicService extends ChangeNotifier {
  LocalMusicService({Directory? directory}) : _directory = directory;
  static final instance = LocalMusicService();
  Directory? _directory;
  Future<void>? _initializing;
  final Map<String, DownloadedSong> _entries = {};
  List<Song> get songs =>
      _entries.values.map((e) => e.song).toList(growable: false);
  Future<Directory> _root() async {
    final root = _directory ??= Directory(
        '${(await getApplicationSupportDirectory()).path}/local-music');
    await root.create(recursive: true);
    return root;
  }

  Future<void> initialize() => _initializing ??= _load();
  Future<void> _load() async {
    final root = await _root();
    final manifest = File('${root.path}/library.json');
    if (!await manifest.exists()) return;
    final list = jsonDecode(await manifest.readAsString()) as List;
    for (final json in list.whereType<Map>()) {
      final entry = DownloadedSong.fromJson(Map<String, dynamic>.from(json));
      if (entry.song.source != 'local' ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(entry.song.id)) {
        continue;
      }
      // Never trust a stored absolute file path for playback/deletion.
      final owned = File('${root.path}/${entry.song.id}.audio');
      if (await owned.exists()) {
        _entries[entry.song.id] = DownloadedSong(
            song: entry.song,
            path: owned.path,
            quality: 'local',
            sizeBytes: entry.sizeBytes,
            downloadedAt: entry.downloadedAt);
      }
    }
    notifyListeners();
  }

  Future<int> importFiles(List<XFile> files) async {
    await initialize();
    final root = await _root();
    var added = 0;
    for (final file in files) {
      final hash = (await sha256.bind(file.openRead()).first).toString();
      if (_entries.containsKey(hash)) continue;
      final target = File('${root.path}/$hash.audio');
      await file.saveTo('${target.path}.part');
      await File('${target.path}.part').rename(target.path);
      final filename = file.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
      final parts = filename.split(' - ');
      final song = Song(
          id: hash,
          source: 'local',
          name: parts.length > 1 ? parts.skip(1).join(' - ') : filename,
          artists: [
            Artist(id: 0, name: parts.length > 1 ? parts.first : '本地音乐')
          ],
          album: const Album(id: 0, name: '本地音乐'),
          durationMs: 0);
      _entries[hash] = DownloadedSong(
          song: song,
          path: target.path,
          quality: 'local',
          sizeBytes: await target.length(),
          downloadedAt: DateTime.now());
      // Persist each file; a later failed import must not lose earlier imports.
      await _save();
      added++;
      notifyListeners();
    }
    return added;
  }

  Future<LocalAudio?> localAudioFor(Song song) async {
    if (song.source != 'local') return null;
    await initialize();
    final entry = _entries[song.id];
    if (entry == null || !await File(entry.path).exists()) return null;
    return LocalAudio(
        file: File(entry.path),
        identity: const AudioIdentity(source: 'local'),
        quality: 'local');
  }

  Future<void> remove(Song song) async {
    await initialize();
    final entry = _entries[song.id];
    if (entry == null) return;
    final file = File(entry.path);
    if (await file.exists()) await file.delete();
    _entries.remove(song.id);
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    final root = await _root();
    final temp = File('${root.path}/library.json.tmp');
    await temp.writeAsString(
        jsonEncode(_entries.values.map((e) => e.toJson()).toList()),
        flush: true);
    await temp.rename('${root.path}/library.json');
  }
}
