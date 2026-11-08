import 'dart:io';
import 'dart:convert';

import 'package:duck_music/core/api/music_api.dart';
import 'package:duck_music/core/models/song.dart';
import 'package:duck_music/core/models/playback_info.dart';
import 'package:duck_music/core/services/song_download_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('song download writes audio and reuses an existing file', () async {
    final directory = await Directory.systemTemp.createTemp('song-download-');
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final service = SongDownloadService.forTesting(
      musicApi: _DownloadMusicApi(),
      client: MockClient((request) async {
        expect(request.url.toString(), 'https://example.com/audio');
        expect(request.headers['Referer'], 'https://www.kuwo.cn/');
        return http.Response.bytes(
          const [1, 2, 3, 4],
          200,
          headers: const {'content-type': 'audio/mpeg'},
        );
      }),
      downloadsDirectory: () async => directory,
    );
    final song = Song(
      id: 'download-id',
      name: '测试/歌曲',
      source: 'netease',
      artists: const [Artist(id: 1, name: '歌手')],
      album: const Album(id: 1, name: '专辑'),
      durationMs: 180000,
    );

    final first = await service.download(song, quality: 'exhigh');
    expect(first.alreadyExists, isFalse);
    expect(
      first.file.path,
      endsWith('netease_download-id_测试_歌曲 - 歌手.mp3'),
    );
    expect(await first.file.readAsBytes(), const [1, 2, 3, 4]);
    expect(service.downloads.single.song.id, 'download-id');
    expect(service.downloads.single.audioIdentity?.id, 'download-recording');
    expect(await service.localFileFor(song), isNotNull);

    final second = await service.download(song, quality: 'exhigh');
    expect(second.alreadyExists, isTrue);
    expect(second.file.path, first.file.path);

    final restored = SongDownloadService.forTesting(
      musicApi: _DownloadMusicApi(),
      client: MockClient((_) async => http.Response('', 500)),
      downloadsDirectory: () async => directory,
    );
    await restored.initialize();
    expect(restored.downloads.single.song.name, '测试/歌曲');
    expect((await restored.localFileFor(song))?.path, first.file.path);
    final localAudio = await restored.localAudioFor(song);
    expect(localAudio?.identity.source, 'kuwo');
    expect(localAudio?.identity.id, 'download-recording');
    expect(localAudio?.identity.canLoadLyrics, isTrue);

    await restored.delete(restored.downloads.single);
    expect(restored.downloads, isEmpty);
    expect(await first.file.exists(), isFalse);
  });

  test('legacy download manifests cannot assume original lyric identity',
      () async {
    final directory = await Directory.systemTemp.createTemp('legacy-download-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/legacy.mp3')..writeAsBytesSync([1]);
    final song = Song(
      id: 'legacy',
      name: 'Legacy',
      source: 'netease',
      artists: const [],
      album: const Album(id: 0, name: ''),
      durationMs: 180000,
    );
    final entry = DownloadedSong(
      song: song,
      path: file.path,
      quality: 'exhigh',
      sizeBytes: 1,
      downloadedAt: DateTime(2026),
    ).toJson()
      ..remove('audioIdentity');
    await File('${directory.path}/.downloads.json')
        .writeAsString(jsonEncode([entry]));
    final service = SongDownloadService.forTesting(
      musicApi: _DownloadMusicApi(),
      client: MockClient((_) async => http.Response('', 500)),
      downloadsDirectory: () async => directory,
    );
    final local = await service.localAudioFor(song);
    expect(local?.file.path, file.path);
    expect(local?.identity.canLoadLyrics, isFalse);
  });
}

class _DownloadMusicApi extends MusicApi {
  @override
  Future<PlaybackInfo> getPlaybackInfo(
    String id, {
    String source = 'netease',
    String quality = 'exhigh',
    bool prefetch = false,
  }) async {
    expect(id, 'download-id');
    expect(source, 'netease');
    expect(quality, 'exhigh');
    expect(prefetch, isTrue);
    return PlaybackInfo.fromJson({
      'playUrl': 'https://example.com/audio',
      'actualSource': 'kuwo',
      'actualId': 'download-recording',
      'lyricMatch': 'exact',
      'durationSec': 181,
    }, id: id, source: source);
  }
}
