import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/membership_api.dart';
import '../../core/api/user_api.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/models/membership.dart';
import '../../core/models/song.dart';
import '../../widgets/glass.dart';
import '../../widgets/user_avatar.dart';
import '../library/downloads_view.dart';
import '../settings/account_security_view.dart';
import '../settings/settings_components.dart';
import '../settings/settings_view.dart';
import '../tools/tools_view.dart';
import 'edit_profile_view.dart';
import 'login_view.dart';
import 'user_library_view.dart';
import 'user_playlists_view.dart';

/// 个人中心。嵌入主框架时保留侧栏和全局播放栏。
class ProfileView extends StatefulWidget {
  const ProfileView({
    super.key,
    this.embedded = false,
    this.onOpenFavorites,
    this.onOpenHistory,
  });

  final bool embedded;
  final VoidCallback? onOpenFavorites;
  final VoidCallback? onOpenHistory;

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  AuthController? _membershipAuth;
  String? _membershipToken;
  int? _membershipGeneration;
  int _membershipRequestVersion = 0;
  Membership? _membership;
  bool _membershipLoading = false;
  bool _membershipError = false;

  @override
  Widget build(BuildContext context) {
    final content = ColoredBox(
      color: _profileBackground(context),
      child: Column(
        children: [
          if (widget.embedded)
            _ProfileHeader(onSettings: () => _openSettings(context))
          else
            GAppBar(
              title: '我的',
              onBack: () => Navigator.of(context).maybePop(),
              transparent: true,
              actions: [
                GToolbarButton(
                  icon: Icons.settings_outlined,
                  tooltip: '设置',
                  onTap: () => _openSettings(context),
                ),
              ],
            ),
          Expanded(child: _buildContent(context)),
        ],
      ),
    );
    return widget.embedded
        ? Material(type: MaterialType.transparency, child: content)
        : Scaffold(body: content);
  }

  Widget _buildContent(BuildContext context) {
    final auth = context.watch<AuthController>();
    final name = auth.username ?? '未登录';
    final token = auth.token;
    final generation = auth.sessionGeneration;
    if (!identical(_membershipAuth, auth) ||
        _membershipToken != token ||
        _membershipGeneration != generation) {
      _membershipAuth = auth;
      _membershipToken = token;
      _membershipGeneration = generation;
      final requestVersion = ++_membershipRequestVersion;
      _membership = null;
      _membershipLoading = false;
      _membershipError = false;
      if (token != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_isCurrentMembershipRequest(
            auth,
            token,
            generation,
            requestVersion,
          )) {
            _loadMembership();
          }
        });
      }
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(
          20, 4, 20, 40 + FloatingDockInsets.bottomOf(context)),
      children: [
        const SettingsSection('账户'),
        _AccountCard(
          name: name,
          email: auth.email,
          avatarUrl: auth.avatarUrl,
          loggedIn: auth.isLoggedIn,
          membershipLoading: _membershipLoading,
          membershipText: _membershipText(),
          membershipActive: _membership?.active == true,
          onAccountTap: auth.isLoggedIn
              ? () => _openPage(context, const EditProfileView())
              : () => _openLogin(context),
          onMembershipTap: auth.isLoggedIn
              ? (_membershipError ? _loadMembership : null)
              : () => _openLogin(context),
        ),
        const SettingsSection('我的音乐'),
        SettingsGroup(
          children: [
            SettingsRow(
              icon: Icons.favorite_rounded,
              iconColor: AppBrand.favoriteRed,
              fixedIconColor: AppBrand.favoriteRed,
              title: '喜欢的音乐',
              onTap: widget.onOpenFavorites ??
                  () => _openSongLibrary(context, favorites: true),
            ),
            SettingsRow(
              icon: Icons.queue_music_rounded,
              iconColor: const Color(0xFF625BE8),
              title: '我的歌单',
              onTap: () => _openPlaylists(
                context,
                filter: UserPlaylistFilter.owned,
              ),
            ),
            SettingsRow(
              icon: Icons.bookmark_rounded,
              iconColor: AppBrand.favoriteRed,
              fixedIconColor: AppBrand.favoriteRed,
              title: '收藏的歌单',
              onTap: () => _openPlaylists(
                context,
                filter: UserPlaylistFilter.favorites,
              ),
            ),
            SettingsRow(
              icon: Icons.history_rounded,
              iconColor: const Color(0xFF5C78D3),
              title: '播放历史',
              onTap: widget.onOpenHistory ??
                  () => _openSongLibrary(context, favorites: false),
            ),
            SettingsRow(
              icon: Icons.download_for_offline_rounded,
              iconColor: const Color(0xFF30A9D8),
              title: '下载管理',
              onTap: () => _openPage(context, const DownloadsView()),
            ),
          ],
        ),
        const SettingsSection('更多'),
        SettingsGroup(
          children: [
            SettingsRow(
              icon: Icons.handyman_rounded,
              iconColor: const Color(0xFFAD54D8),
              title: '工具箱',
              subtitle: 'AI 绘画、视频解析与歌单导入',
              onTap: () => _openPage(context, const ToolsView()),
            ),
            SettingsRow(
              icon: Icons.shield_outlined,
              iconColor: const Color(0xFF31BF5A),
              title: '账号安全',
              subtitle: '登录设备、密码与账号管理',
              onTap: auth.isLoggedIn
                  ? () => _openPage(context, const AccountSecurityView())
                  : () => _openLogin(context),
            ),
          ],
        ),
      ],
    );
  }

  Color _profileBackground(BuildContext context) {
    return Theme.of(context).colorScheme.surfaceContainerLowest;
  }

  void _openLogin(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginView()),
    );
  }

  Future<void> _openSongLibrary(
    BuildContext context, {
    required bool favorites,
  }) async {
    final token = context.read<AuthController>().token;
    if (token == null) {
      _openLogin(context);
      return;
    }
    await _openPage(
      context,
      UserLibraryView(
        title: favorites ? '喜欢的音乐' : '播放历史',
        kind: favorites ? UserLibraryKind.favorites : UserLibraryKind.history,
        loader: () async {
          final items = favorites
              ? await UserApi().getFavorites(token)
              : await UserApi().getHistory(token);
          return items.map(itemToSong).toList();
        },
        onRemove: (song) => _removeLibrarySong(
          song,
          token: token,
          favorites: favorites,
        ),
        onClear: favorites
            ? null
            : (songs) async {
                for (final song in songs) {
                  final recordId = song.libraryId;
                  if (recordId != null) {
                    await UserApi().deleteHistory(recordId, token);
                  }
                }
              },
      ),
    );
  }

  Future<void> _removeLibrarySong(
    Song song, {
    required String token,
    required bool favorites,
  }) async {
    if (favorites) {
      await UserApi().removeFavorite(song.id, song.source, token);
      return;
    }
    final recordId = song.libraryId;
    if (recordId != null) await UserApi().deleteHistory(recordId, token);
  }

  void _openPlaylists(
    BuildContext context, {
    required UserPlaylistFilter filter,
  }) {
    if (context.read<AuthController>().token == null) {
      _openLogin(context);
      return;
    }
    _openPage(context, UserPlaylistsView(filter: filter));
  }

  Future<void> _openPage(BuildContext context, Widget page) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  void _openSettings(BuildContext context) {
    _openPage(context, const SettingsView());
  }

  bool _isCurrentMembershipRequest(
    AuthController auth,
    String token,
    int generation,
    int requestVersion,
  ) {
    return mounted &&
        identical(_membershipAuth, auth) &&
        _membershipToken == token &&
        _membershipGeneration == generation &&
        auth.token == token &&
        auth.sessionGeneration == generation &&
        _membershipRequestVersion == requestVersion;
  }

  Future<void> _loadMembership() async {
    final auth = _membershipAuth;
    final token = _membershipToken;
    final generation = _membershipGeneration;
    if (_membershipLoading ||
        auth == null ||
        token == null ||
        generation == null ||
        !_isCurrentMembershipRequest(
          auth,
          token,
          generation,
          _membershipRequestVersion,
        )) {
      return;
    }
    final requestVersion = ++_membershipRequestVersion;
    bool isCurrent() =>
        _isCurrentMembershipRequest(auth, token, generation, requestVersion);
    setState(() {
      _membershipLoading = true;
      _membershipError = false;
    });
    try {
      final membership = await MembershipApi().getMembership(token);
      if (isCurrent()) {
        setState(() {
          _membership = membership;
          _membershipError = false;
        });
      }
    } catch (_) {
      if (isCurrent()) {
        setState(() => _membershipError = true);
      }
    } finally {
      if (isCurrent()) setState(() => _membershipLoading = false);
    }
  }

  String _membershipText() {
    if (_membershipLoading) return '加载中...';
    if (_membershipError) return '状态获取失败，点击重试';
    final membership = _membership;
    if (membership == null) return '加载中...';
    if (!membership.active) return '尚未开通会员';
    if (membership.lifetime) return '${membership.typeName ?? '永久'} · 长期有效';
    final expiresAt = membership.expiresAt;
    if (expiresAt == null) return membership.typeName ?? '有效会员';
    final date =
        '${expiresAt.year}-${expiresAt.month.toString().padLeft(2, '0')}'
        '-${expiresAt.day.toString().padLeft(2, '0')}';
    return '${membership.typeName ?? '会员'} · 有效期至 $date';
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.name,
    required this.email,
    required this.avatarUrl,
    required this.loggedIn,
    required this.membershipLoading,
    required this.membershipText,
    required this.membershipActive,
    required this.onAccountTap,
    required this.onMembershipTap,
  });

  final String name;
  final String? email;
  final String? avatarUrl;
  final bool loggedIn;
  final bool membershipLoading;
  final String membershipText;
  final bool membershipActive;
  final VoidCallback onAccountTap;
  final VoidCallback? onMembershipTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cardColor = scheme.surfaceContainer;
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          GPressScale(
            onTap: onAccountTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 88),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    UserAvatar(
                      radius: 26,
                      name: name,
                      showInitial: loggedIn,
                      imageUrl: loggedIn ? avatarUrl : null,
                      backgroundColor: membershipActive
                          ? scheme.primaryContainer
                          : scheme.surfaceContainerHighest,
                      foregroundColor: membershipActive
                          ? scheme.onPrimaryContainer
                          : loggedIn
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 20,
                              height: 1.2,
                              fontWeight: TypeScale.semibold,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            loggedIn && email != null && email!.isNotEmpty
                                ? email!
                                : loggedIn
                                    ? name
                                    : '登录后同步收藏与歌单',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      loggedIn ? Icons.edit_rounded : Icons.login_rounded,
                      size: 19,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 58, right: 16),
            child: Divider(
              height: 0.5,
              thickness: 0.5,
              color: glassHairline(context),
            ),
          ),
          SettingsRow(
            icon: Icons.star_rounded,
            iconColor: const Color(0xFFC8A348),
            title: '会员权益',
            subtitle: membershipLoading
                ? '正在读取会员状态'
                : loggedIn
                    ? membershipText
                    : '登录后查看会员状态',
            value: loggedIn ? null : '登录',
            onTap: onMembershipTap,
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return GPageHeader(
      title: '我的',
      inlineActions: true,
      actions: [
        GToolbarButton(
          icon: Icons.settings_outlined,
          tooltip: '设置',
          backgroundColor: Colors.transparent,
          onTap: onSettings,
        ),
      ],
    );
  }
}
