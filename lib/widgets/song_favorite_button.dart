import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api/user_api.dart';
import '../core/auth/auth_controller.dart';
import '../core/models/song.dart';
import '../core/player/player_controller.dart';
import '../core/services/user_playlist_library.dart';
import 'glass.dart';

final _favoriteSnapshots = Expando<_FavoriteSnapshot>();

class _FavoriteSnapshot {
  _FavoriteSnapshot(this.token, this.generation, this.revision)
      : songs = UserApi().getFavorites(token).then((items) => items
            .map((item) =>
                '${item['source'] ?? 'netease'}:${item['songId'] ?? item['id']}')
            .toSet());

  final String token;
  final int generation;
  final int revision;
  final Future<Set<String>> songs;
}

/// One favorite snapshot per account/library revision, shared by visible rows.
class SongFavoriteButton extends StatefulWidget {
  const SongFavoriteButton({super.key, required this.song});
  final Song song;

  @override
  State<SongFavoriteButton> createState() => _SongFavoriteButtonState();
}

class _SongFavoriteButtonState extends State<SongFavoriteButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController?>();
    final token = auth?.token;
    if (auth == null || token == null) {
      return _button(false, () => _message('请先登录后再收藏'));
    }
    return ListenableBuilder(
      listenable: UserPlaylistLibrary.instance,
      builder: (context, _) {
        final revision = UserPlaylistLibrary.instance.revision;
        var cached = _favoriteSnapshots[auth];
        if (cached == null ||
            cached.token != token ||
            cached.generation != auth.sessionGeneration ||
            cached.revision != revision) {
          cached = _FavoriteSnapshot(token, auth.sessionGeneration, revision);
          _favoriteSnapshots[auth] = cached;
        }
        return FutureBuilder<Set<String>>(
          key: ValueKey((auth, token, auth.sessionGeneration, revision)),
          future: cached.songs,
          builder: (context, snapshot) {
            final liked = snapshot.data
                    ?.contains('${widget.song.source}:${widget.song.id}') ??
                false;
            if (snapshot.hasError) {
              return _button(
                  false, () => setState(() => _favoriteSnapshots[auth] = null),
                  retry: true);
            }
            return _button(liked,
                !snapshot.hasData || _busy ? null : () => _toggle(auth, liked));
          },
        );
      },
    );
  }

  Widget _button(bool liked, VoidCallback? onTap, {bool retry = false}) =>
      GIconButton(
        icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        tooltip:
            '${retry ? '重试收藏状态' : liked ? '取消收藏' : '收藏歌曲'}：${widget.song.name}',
        size: 22,
        padding: 12,
        tint: liked
            ? AppBrand.favoriteRed
            : Theme.of(context).colorScheme.onSurfaceVariant,
        backgroundColor: Colors.transparent,
        onTap: onTap,
      );

  Future<void> _toggle(AuthController auth, bool liked) async {
    if (_busy) return;
    final token = auth.token;
    if (token == null) return;
    final generation = auth.sessionGeneration;
    final song = widget.song;
    setState(() => _busy = true);
    try {
      final api = UserApi();
      if (liked) {
        await api.removeFavorite(song.id, song.source, token);
      } else {
        await api.addFavorite(song, token);
      }
      if (!mounted ||
          !identical(context.read<AuthController>(), auth) ||
          auth.sessionGeneration != generation) {
        return;
      }
      final player = context.read<PlayerController>();
      if (player.current?.id == song.id &&
          player.current?.source == song.source) {
        player.setLiked(!liked);
      }
      _message(liked ? '已取消收藏' : '已加入喜欢的音乐');
    } catch (_) {
      if (mounted &&
          identical(context.read<AuthController>(), auth) &&
          auth.sessionGeneration == generation) {
        _message('收藏操作失败，请重试');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String message) => ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
