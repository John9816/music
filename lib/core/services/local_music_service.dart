import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import '../models/song.dart';
import '../models/playback_info.dart';
import 'song_download_service.dart';
import 'device_music_library.dart';

class LocalMusicService extends ChangeNotifier with WidgetsBindingObserver {
  LocalMusicService({Directory? directory, DeviceMusicLibrary? deviceLibrary})
      : _directory = directory,
        _deviceLibrary = deviceLibrary ?? AndroidDeviceMusicLibrary();
  static final instance = LocalMusicService();
  Directory? _directory;
  Future<void>? _initializing;
  final Map<String, DownloadedSong> _entries = {};
  final DeviceMusicLibrary _deviceLibrary;
  final Map<String, (Song, Uri)> _deviceSongs = {};
  final Set<String> _hiddenDeviceSongs = {};
  StreamSubscription<void>? _changes;
  Timer? _rescanDebounce;
  Future<void>? _scanning;
  bool _scanAgain = false, _requestPermission = false, _disposed = false;
  bool _observing = false, devicePermissionGranted = false;
  String? scanError;
  bool get supportsDeviceScan => _deviceLibrary.supported;
  bool get scanning => _scanning != null;
  List<Song> get songs => [
        ..._deviceSongs.values.map((e) => e.$1),
        ..._entries.values.map((e) => e.song)
      ];

  Future<void> startAutomaticScan() async {
    if (!supportsDeviceScan || _disposed) return;
    if (!_observing) {
      _observing = true;
      WidgetsBinding.instance.addObserver(this);
      _changes = _deviceLibrary.changes
          .listen((_) => _scheduleScan(), onError: (Object _) {});
    }
    try {
      await scanDevice();
    } catch (_) {
      scanError = '本地音乐读取失败，请重试';
      if (!_disposed) notifyListeners();
    }
  }

  void _scheduleScan() {
    if (_disposed) return;
    _rescanDebounce?.cancel();
    _rescanDebounce =
        Timer(const Duration(milliseconds: 650), () => scanDevice());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _scheduleScan();
  }

  Future<void> scanDevice({bool requestPermission = false}) async {
    if (!supportsDeviceScan || _disposed) return;
    await initialize();
    if (_disposed) return;
    _requestPermission |= requestPermission;
    if (_scanning != null) {
      _scanAgain = true;
      return _scanning;
    }
    final completion = Completer<void>();
    _scanning = completion.future;
    notifyListeners();
    try {
      do {
        _scanAgain = false;
        final ask = _requestPermission;
        _requestPermission = false;
        final snapshot = await _deviceLibrary.scan(requestPermission: ask);
        if (_disposed) break;
        devicePermissionGranted = snapshot.granted;
        scanError = null;
        final next = <String, (Song, Uri)>{};
        if (snapshot.granted) {
          for (final data in snapshot.tracks) {
            final uri = Uri.tryParse(data['uri']?.toString() ?? '');
            if (uri == null ||
                uri.scheme != 'content' ||
                uri.host != 'media' ||
                !RegExp(r'^/[^/]+/audio/media/\d+$').hasMatch(uri.path) ||
                uri.hasQuery ||
                uri.hasFragment) {
              continue;
            }
            final id = 'device:${uri.path}';
            if (_hiddenDeviceSongs.contains(id)) continue;
            final song = Song.fromV1({
              'id': id,
              'source': 'local',
              'name': data['title'] ?? '未知歌曲',
              'artist': data['artist'] == '<unknown>' ? '未知歌手' : data['artist'],
              'album': data['album'] == '<unknown>' ? '本地音乐' : data['album'],
              'durationMs': data['durationMs'],
            });
            next[id] = (song, uri);
          }
        }
        _deviceSongs
          ..clear()
          ..addAll(next);
      } while (_scanAgain && !_disposed);
    } catch (_) {
      // An unsuccessful query must not replace a previously valid index.
      scanError = '扫描失败，请重试或检查音乐权限';
    } finally {
      _scanning = null;
      completion.complete();
      if (!_disposed) notifyListeners();
    }
  }

  Future<Uri?> playbackUriFor(Song song) async {
    if (song.source != 'local') return null;
    await initialize();
    if (song.id.startsWith('device:')) {
      if (_deviceSongs.isEmpty) await scanDevice();
      return _deviceSongs[song.id]?.$2;
    }
    return (await localAudioFor(song))?.file.uri;
  }

  Future<Directory> _root() async {
    final root = _directory ??= Directory(
        '${(await getApplicationSupportDirectory()).path}/local-music');
    await root.create(recursive: true);
    return root;
  }

  Future<void> initialize() => _initializing ??= _load();
  Future<void> _load() async {
    final root = await _root();
    final hidden = File('${root.path}/hidden-device-songs.json');
    if (await hidden.exists()) {
      _hiddenDeviceSongs.addAll(
          (jsonDecode(await hidden.readAsString()) as List)
              .whereType<String>());
    }
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
    if (song.id.startsWith('device:')) {
      _hiddenDeviceSongs.add(song.id);
      _deviceSongs.remove(song.id);
      final root = await _root();
      final temp = File('${root.path}/hidden-device-songs.json.tmp');
      await temp.writeAsString(jsonEncode(_hiddenDeviceSongs.toList()),
          flush: true);
      await temp.rename('${root.path}/hidden-device-songs.json');
      notifyListeners();
      return;
    }
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

  @override
  void dispose() {
    _disposed = true;
    _rescanDebounce?.cancel();
    _changes?.cancel();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
