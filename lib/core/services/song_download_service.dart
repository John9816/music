import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../api/music_api.dart';
import '../models/song.dart';
import 'cache_service.dart';

class SongDownloadResult {
  const SongDownloadResult({required this.file, required this.alreadyExists});

  final File file;
  final bool alreadyExists;
}

class DownloadedSong {
  const DownloadedSong({
    required this.song,
    required this.path,
    required this.quality,
    required this.sizeBytes,
    required this.downloadedAt,
  });

  final Song song;
  final String path;
  final String quality;
  final int sizeBytes;
  final DateTime downloadedAt;

  Map<String, dynamic> toJson() => {
        'song': {
          'id': song.id,
          'name': song.name,
          'source': song.source,
          'artists': [
            for (final artist in song.artists)
              {'id': artist.id, 'name': artist.name, 'picUrl': artist.picUrl},
          ],
          'album': {
            'id': song.album.id,
            'name': song.album.name,
            'picUrl': song.album.picUrl,
          },
          'durationMs': song.durationMs,
        },
        'path': path,
        'quality': quality,
        'sizeBytes': sizeBytes,
        'downloadedAt': downloadedAt.toIso8601String(),
      };

  factory DownloadedSong.fromJson(Map<String, dynamic> json) {
    final songJson = Map<String, dynamic>.from(json['song'] as Map);
    final albumJson = Map<String, dynamic>.from(songJson['album'] as Map);
    final artistsJson = (songJson['artists'] as List? ?? const []);
    return DownloadedSong(
      song: Song(
        id: songJson['id'].toString(),
        name: songJson['name'].toString(),
        source: songJson['source'].toString(),
        artists: artistsJson
            .map((value) => Map<String, dynamic>.from(value as Map))
            .map(
              (artist) => Artist(
                id: (artist['id'] as num?)?.toInt() ?? 0,
                name: artist['name']?.toString() ?? '未知歌手',
                picUrl: artist['picUrl']?.toString(),
              ),
            )
            .toList(),
        album: Album(
          id: (albumJson['id'] as num?)?.toInt() ?? 0,
          name: albumJson['name']?.toString() ?? '',
          picUrl: albumJson['picUrl']?.toString(),
        ),
        durationMs: (songJson['durationMs'] as num?)?.toInt() ?? 0,
      ),
      path: json['path'].toString(),
      quality: json['quality']?.toString() ?? 'exhigh',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      downloadedAt: DateTime.tryParse(json['downloadedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class SongDownloadService extends ChangeNotifier {
  SongDownloadService._({
    required MusicApi musicApi,
    required http.Client client,
    required Future<Directory> Function() downloadsDirectory,
  })  : _musicApi = musicApi,
        _client = client,
        _downloadsDirectory = downloadsDirectory;

  static final SongDownloadService instance = SongDownloadService._(
    musicApi: MusicApi(),
    client: http.Client(),
    downloadsDirectory: () => CacheService.instance.downloadsDirectory,
  );

  @visibleForTesting
  factory SongDownloadService.forTesting({
    required MusicApi musicApi,
    required http.Client client,
    required Future<Directory> Function() downloadsDirectory,
  }) = SongDownloadService._;

  static const _manifestName = '.downloads.json';
  final MusicApi _musicApi;
  final http.Client _client;
  final Future<Directory> Function() _downloadsDirectory;
  final Map<String, DownloadedSong> _downloads = {};
  final Map<String, double> _progress = {};
  Future<void>? _initializing;

  List<DownloadedSong> get downloads {
    final values = _downloads.values.toList()
      ..sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));
    return List.unmodifiable(values);
  }

  Map<String, double> get progress => Map.unmodifiable(_progress);
  bool get initialized => _initializing != null;
  String keyFor(Song song) => '${song.source}:${song.id}';
  bool isDownloading(Song song) => _progress.containsKey(keyFor(song));
  bool isDownloaded(Song song) => _downloads.containsKey(keyFor(song));

  Future<void> initialize() => _initializing ??= _loadManifest();

  Future<File?> localFileFor(Song song) async {
    await initialize();
    final entry = _downloads[keyFor(song)];
    if (entry == null) return null;
    final file = File(entry.path);
    if (await file.exists() && await file.length() > 0) return file;
    _downloads.remove(keyFor(song));
    await _saveManifest();
    notifyListeners();
    return null;
  }

  Future<SongDownloadResult> download(
    Song song, {
    required String quality,
    ValueChanged<double>? onProgress,
  }) async {
    await initialize();
    final existing = await localFileFor(song);
    if (existing != null) {
      return SongDownloadResult(file: existing, alreadyExists: true);
    }
    final key = keyFor(song);
    if (_progress.containsKey(key)) throw Exception('歌曲正在下载中');
    _progress[key] = 0;
    notifyListeners();

    File? partial;
    IOSink? sink;
    try {
      final url = await _musicApi.getSongUrl(
        song.id,
        source: song.source,
        quality: quality,
      );
      if (url == null || url.isEmpty) throw Exception('未获取到下载地址');
      final request = http.Request('GET', Uri.parse(url));
      final response = await _client.send(request).timeout(
            const Duration(seconds: 25),
          );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('下载失败（HTTP ${response.statusCode}）');
      }

      final directory = await _downloadsDirectory();
      if (!await directory.exists()) await directory.create(recursive: true);
      final extension = _extensionFor(
        response.headers['content-type'],
        Uri.parse(url).path,
        quality,
      );
      final prefix = _safeFileName('${song.source}_${song.id}');
      final title = _safeFileName('${song.name} - ${song.artistNames}');
      final target = File('${directory.path}/${prefix}_$title.$extension');
      partial = File('${target.path}.part');
      sink = partial.openWrite();
      final total = response.contentLength ?? 0;
      var received = 0;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        final value = total > 0 ? received / total : 0.0;
        _progress[key] = value;
        onProgress?.call(value);
        notifyListeners();
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (await target.exists()) await target.delete();
      final file = await partial.rename(target.path);
      partial = null;
      _downloads[key] = DownloadedSong(
        song: song,
        path: file.path,
        quality: quality,
        sizeBytes: await file.length(),
        downloadedAt: DateTime.now(),
      );
      await _saveManifest();
      onProgress?.call(1);
      return SongDownloadResult(file: file, alreadyExists: false);
    } catch (_) {
      await sink?.close();
      if (partial != null && await partial.exists()) await partial.delete();
      rethrow;
    } finally {
      _progress.remove(key);
      notifyListeners();
    }
  }

  Future<void> delete(DownloadedSong entry) async {
    final file = File(entry.path);
    if (await file.exists()) await file.delete();
    _downloads.remove(keyFor(entry.song));
    await _saveManifest();
    notifyListeners();
  }

  Future<void> clear() async {
    await initialize();
    for (final entry in _downloads.values) {
      final file = File(entry.path);
      if (await file.exists()) await file.delete();
    }
    _downloads.clear();
    await _saveManifest();
    notifyListeners();
  }

  Future<void> _loadManifest() async {
    final directory = await _downloadsDirectory();
    if (!await directory.exists()) await directory.create(recursive: true);
    final manifest = File('${directory.path}/$_manifestName');
    if (!await manifest.exists()) {
      notifyListeners();
      return;
    }
    try {
      final values = jsonDecode(await manifest.readAsString()) as List;
      for (final value in values) {
        final entry = DownloadedSong.fromJson(
          Map<String, dynamic>.from(value as Map),
        );
        if (await File(entry.path).exists()) {
          _downloads[keyFor(entry.song)] = entry;
        }
      }
    } catch (_) {
      _downloads.clear();
    }
    notifyListeners();
  }

  Future<void> _saveManifest() async {
    final directory = await _downloadsDirectory();
    if (!await directory.exists()) await directory.create(recursive: true);
    final manifest = File('${directory.path}/$_manifestName');
    final temporary = File('${manifest.path}.tmp');
    await temporary.writeAsString(
      jsonEncode(_downloads.values.map((entry) => entry.toJson()).toList()),
      flush: true,
    );
    if (await manifest.exists()) await manifest.delete();
    await temporary.rename(manifest.path);
  }

  String _extensionFor(String? contentType, String path, String quality) {
    final normalizedType = contentType?.toLowerCase() ?? '';
    if (normalizedType.contains('flac')) return 'flac';
    if (normalizedType.contains('mp4') || normalizedType.contains('m4a')) {
      return 'm4a';
    }
    if (normalizedType.contains('aac')) return 'aac';
    if (normalizedType.contains('mpeg')) return 'mp3';
    final pathExtension = RegExp(r'\.([A-Za-z0-9]{2,5})$')
        .firstMatch(path)
        ?.group(1)
        ?.toLowerCase();
    if (const {'mp3', 'flac', 'm4a', 'aac', 'wav'}.contains(pathExtension)) {
      return pathExtension!;
    }
    return quality == 'lossless' || quality == 'hires' ? 'flac' : 'mp3';
  }

  String _safeFileName(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return 'song';
    return cleaned.length <= 100 ? cleaned : cleaned.substring(0, 100).trim();
  }
}
