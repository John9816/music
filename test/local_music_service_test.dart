import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:duck_music/core/services/local_music_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('import copies content, deduplicates and removal preserves original file', () async {
    final root = await Directory.systemTemp.createTemp('local-music-test');
    addTearDown(() => root.delete(recursive: true));
    final original = File('${root.path}/Artist - Song.mp3');
    await original.writeAsBytes([73, 68, 51, 1, 2, 3]);
    final service = LocalMusicService(directory: Directory('${root.path}/library'));
    await service.importFiles([XFile(original.path), XFile(original.path)]);
    expect(service.songs, hasLength(1));
    final song = service.songs.single;
    expect(song.name, 'Song');
    expect(song.artistNames, 'Artist');
    expect((await service.localAudioFor(song))!.file.path, isNot(original.path));
    final restarted = LocalMusicService(directory: Directory('${root.path}/library'));
    await restarted.initialize();
    expect(restarted.songs.single.id, song.id);
    await restarted.remove(song);
    expect(await original.exists(), isTrue);
    expect(restarted.songs, isEmpty);
  });
}
