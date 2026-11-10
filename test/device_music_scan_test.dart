import 'dart:async';
import 'dart:io';
import 'package:duck_music/core/services/device_music_library.dart';
import 'package:duck_music/core/services/local_music_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _Library implements DeviceMusicLibrary {
  DeviceMusicSnapshot result = const DeviceMusicSnapshot(granted: false);
  final events = StreamController<void>.broadcast();
  int calls = 0;
  bool fail = false;
  Completer<DeviceMusicSnapshot>? pending;
  @override
  bool get supported => true;
  @override
  Stream<void> get changes => events.stream;
  @override
  Future<DeviceMusicSnapshot> scan({bool requestPermission = false}) async {
    calls++;
    if (fail) throw StateError('MediaStore unavailable');
    if (pending != null) return pending!.future;
    return result;
  }
}

Map<String, dynamic> track(int id, {String title = '本地歌曲'}) => {
      'uri': 'content://media/external/audio/media/$id',
      'title': title,
      'artist': '本地歌手',
      'album': '本地专辑',
      'durationMs': 120000,
      'sizeBytes': 12345,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late _Library library;
  late LocalMusicService service;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('device-library-');
    library = _Library();
    service = LocalMusicService(directory: root, deviceLibrary: library);
  });
  tearDown(() async {
    service.dispose();
    await library.events.close();
    await root.delete(recursive: true);
  });

  test('scans metadata and content URIs without copying device files',
      () async {
    library.result =
        DeviceMusicSnapshot(granted: true, tracks: [track(1), track(1)]);
    await service.scanDevice();
    expect(service.songs, hasLength(1));
    final song = service.songs.single;
    expect(song.artistNames, '本地歌手');
    expect(song.durationMs, 120000);
    expect(await service.playbackUriFor(song), Uri.parse(track(1)['uri']));
    expect(await root.list().where((f) => f.path.endsWith('.audio')).length, 0);
  });

  test('successful rescan reconciles edits and removals', () async {
    library.result =
        DeviceMusicSnapshot(granted: true, tracks: [track(1), track(2)]);
    await service.scanDevice();
    library.result =
        DeviceMusicSnapshot(granted: true, tracks: [track(2, title: '新名称')]);
    await service.scanDevice();
    expect(service.songs.single.name, '新名称');
  });

  test(
      'failed query preserves the last valid index and reports retryable error',
      () async {
    library.result = DeviceMusicSnapshot(granted: true, tracks: [track(1)]);
    await service.scanDevice();
    library.fail = true;
    await service.scanDevice();
    expect(service.songs, hasLength(1));
    expect(service.scanError, isNotNull);
    library.fail = false;
    await service.scanDevice();
    expect(service.scanError, isNull);
  });

  test('revoked audio permission clears inaccessible entries and exposes state',
      () async {
    library.result = DeviceMusicSnapshot(granted: true, tracks: [track(1)]);
    await service.scanDevice();
    library.result = const DeviceMusicSnapshot(granted: false);
    await service.scanDevice();
    expect(service.songs, isEmpty);
    expect(service.devicePermissionGranted, isFalse);
  });

  test(
      'removal hides device track across rescans and restart without deleting it',
      () async {
    library.result =
        DeviceMusicSnapshot(granted: true, tracks: [track(1), track(2)]);
    await service.scanDevice();
    await service.remove(service.songs.first);
    await service.scanDevice();
    expect(service.songs, hasLength(1));
    final restarted =
        LocalMusicService(directory: root, deviceLibrary: library);
    addTearDown(restarted.dispose);
    await restarted.scanDevice();
    expect(restarted.songs, hasLength(1));
  });

  test('scan rejects non-media content and file URLs', () async {
    library.result = DeviceMusicSnapshot(granted: true, tracks: [
      track(1),
      {...track(2), 'uri': 'file:///private/file.mp3'},
      {...track(3), 'uri': 'content://other.provider/audio/3'},
    ]);
    await service.scanDevice();
    expect(service.songs, hasLength(1));
  });

  test('overlapping scans are serialized and reconcile the newest snapshot',
      () async {
    library.pending = Completer<DeviceMusicSnapshot>();
    final first = service.scanDevice();
    await Future<void>.delayed(Duration.zero);
    final second = service.scanDevice();
    final pending = library.pending!;
    library.pending = null;
    library.result = DeviceMusicSnapshot(granted: true, tracks: [track(2)]);
    pending.complete(DeviceMusicSnapshot(granted: true, tracks: [track(1)]));
    await Future.wait([first, second]);
    expect(service.songs.single.id, contains('2'));
  });
}
