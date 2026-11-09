import 'dart:async';
import 'dart:io';

import '../api/user_api.dart';
import '../auth/auth_controller.dart';
import '../models/song.dart';
import '../services/song_download_service.dart';
import '../settings/settings_controller.dart';
import 'car_media_library.dart';
import 'player_controller.dart';
import 'roaming_controller.dart';
import 'system_media_controller.dart';

/// Created before runApp so media hosts can cold-start playback without a view.
class AppPlaybackRuntime {
  AppPlaybackRuntime() {
    settings = SettingsController();
    player = PlayerController(
        settings: settings,
        beforePlayback: Platform.isAndroid || Platform.isIOS
            ? SystemMediaController.instance.prepareForPlayback
            : null);
    auth = AuthController(
        onSessionCleared: () => player.stopAndClear(clearSavedPlayback: true));
    roaming = RoamingController(player: player, auth: auth);
    library = CarMediaLibrary(
        auth: auth,
        player: player,
        settings: settings,
        downloads: SongDownloadService.instance);
    player.onSongPlayed = _recordHistory;
    player.onSongChanged = _syncFavorite;
    if (_hasSystemMedia) SystemMediaController.instance.attach(player);
    ready = _initialize();
  }

  late final SettingsController settings;
  late final PlayerController player;
  late final AuthController auth;
  late final CarMediaLibrary library;
  late final RoamingController roaming;
  late final Future<void> ready;
  bool _disposed = false;
  bool get _hasSystemMedia =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  Future<void> _initialize() async {
    try {
      await Future.wait([settings.load(), auth.load()]);
      if (_disposed) return;
      // Restore local metadata immediately; network playback still uses the active account.
      await player.restoreLastPlayback();
    } catch (_) {
      // A damaged preference or saved queue must not disable the media browser.
    }
    if (_disposed) return;
    if (_hasSystemMedia) SystemMediaController.instance.attachLibrary(library);
  }

  void _recordHistory(Song song) {
    if (song.source == 'local') return;
    final token = auth.token;
    final generation = auth.sessionGeneration;
    if (token == null) return;
    unawaited(UserApi().addHistory(song, token).then((_) {
      if (!_disposed && generation == auth.sessionGeneration) {
        library.refresh(categoryId: CarMediaLibrary.recentId);
      }
    }).catchError((_) {}));
  }

  Future<void> _syncFavorite(Song song) async {
    final token = auth.token;
    final generation = auth.sessionGeneration;
    player.setLiked(false);
    if (token == null) return;
    try {
      final songs = await library.songsFor(CarMediaLibrary.favoritesId);
      if (_disposed ||
          generation != auth.sessionGeneration ||
          player.current?.id != song.id ||
          player.current?.source != song.source) {
        return;
      }
      player.setLiked(songs
          .any((item) => item.id == song.id && item.source == song.source));
    } catch (_) {}
  }

  void dispose() {
    _disposed = true;
    SystemMediaController.instance.detachLibrary(library);
    SystemMediaController.instance.detach(player);
    roaming.dispose();
    library.dispose();
    auth.dispose();
    player.dispose();
    settings.dispose();
  }
}
