import 'package:audio_service/audio_service.dart';
import 'package:duck_music/core/player/audio_source_policy.dart';
import 'package:duck_music/core/player/player_controller.dart';
import 'package:duck_music/core/player/system_media_controller.dart';
import 'package:duck_music/core/models/song.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('position stream remains stable across UI rebuilds', () {
    final player = PlayerController(settings: SettingsController());
    addTearDown(player.dispose);

    expect(identical(player.positionStream, player.positionStream), isTrue);
  });

  test('native platforms use native audio request headers', () {
    expect(usesNativeAudioHeaders(TargetPlatform.android), isTrue);
    expect(usesNativeAudioHeaders(TargetPlatform.iOS), isTrue);
    expect(usesNativeAudioHeaders(TargetPlatform.macOS), isTrue);
    expect(usesNativeAudioHeaders(TargetPlatform.windows), isFalse);
  });

  test('QQ playback quality falls back to supported tiers', () {
    expect(
      playbackQualityCandidates('qq', 'hires'),
      ['hires', 'lossless', 'exhigh', 'standard'],
    );
    expect(
      playbackQualityCandidates('qq', 'lossless'),
      ['lossless', 'exhigh', 'standard'],
    );
    expect(
      playbackQualityCandidates('qq', 'auto'),
      ['exhigh', 'standard'],
    );
    expect(
      playbackQualityCandidates('netease', 'hires'),
      ['hires'],
    );
  });

  test('QQ playback probe rejects API error pages', () {
    expect(isPlayableAudioResponse(206, 'audio/mp4'), isTrue);
    expect(isPlayableAudioResponse(200, 'application/octet-stream'), isTrue);
    expect(isPlayableAudioResponse(500, 'text/html'), isFalse);
    expect(isPlayableAudioResponse(200, 'application/json'), isFalse);
  });

  test('system media controls expose and execute previous and next', () async {
    final settings = SettingsController();
    final player = _SystemMediaPlayer(settings);
    final handler = SystemMediaController()..attach(player);
    addTearDown(() {
      handler.detach(player);
      player.dispose();
      settings.dispose();
    });

    final actions = handler.playbackState.value.controls
        .map((control) => control.action)
        .toList();
    expect(actions, contains(MediaAction.skipToPrevious));
    expect(actions, contains(MediaAction.skipToNext));
    expect(handler.queue.value, hasLength(3));
    expect(handler.playbackState.value.queueIndex, 1);

    await handler.skipToNext();
    expect(player.queueIndex, 2);
    expect(handler.mediaItem.value?.title, '第三首');

    await handler.skipToPrevious();
    expect(player.queueIndex, 1);
    expect(handler.mediaItem.value?.title, '第二首');
  });
}

class _SystemMediaPlayer extends PlayerController {
  _SystemMediaPlayer(SettingsController settings) : super(settings: settings);

  final List<Song> _songs = [
    Song(
      id: 'one',
      name: '第一首',
      source: 'netease',
      artists: const [Artist(id: 1, name: '歌手')],
      album: const Album(id: 1, name: '测试专辑'),
      durationMs: 180000,
    ),
    Song(
      id: 'two',
      name: '第二首',
      source: 'netease',
      artists: const [Artist(id: 1, name: '歌手')],
      album: const Album(id: 1, name: '测试专辑'),
      durationMs: 180000,
    ),
    Song(
      id: 'three',
      name: '第三首',
      source: 'netease',
      artists: const [Artist(id: 1, name: '歌手')],
      album: const Album(id: 1, name: '测试专辑'),
      durationMs: 180000,
    ),
  ];
  int _currentIndex = 1;
  bool _isPlaying = true;
  Duration _position = const Duration(seconds: 12);

  @override
  List<Song> get queue => _songs;

  @override
  int get queueIndex => _currentIndex;

  @override
  Song get current => _songs[_currentIndex];

  @override
  bool get playing => _isPlaying;

  @override
  Duration get position => _position;

  @override
  Future<void> next() async {
    _currentIndex = (_currentIndex + 1) % _songs.length;
    notifyListeners();
  }

  @override
  Future<void> previous() async {
    _currentIndex = (_currentIndex - 1 + _songs.length) % _songs.length;
    notifyListeners();
  }

  @override
  Future<void> playAt(int index) async {
    _currentIndex = index;
    notifyListeners();
  }

  @override
  Future<void> togglePlay() async {
    _isPlaying = !_isPlaying;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    _isPlaying = false;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration position) async {
    _position = position;
    notifyListeners();
  }
}
