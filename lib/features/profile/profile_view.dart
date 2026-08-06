import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api/membership_api.dart';
import '../../core/api/user_api.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/config/app_config.dart';
import '../../core/models/membership.dart';
import '../../core/models/song.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/glass.dart';
import '../../widgets/user_avatar.dart';
import '../library/downloads_view.dart';
import '../settings/account_security_view.dart';
import '../settings/about_view.dart';
import '../settings/desktop_settings_view.dart';
import '../settings/notifications_view.dart';
import '../settings/settings_view.dart';
import '../settings/settings_components.dart';
import '../settings/storage_settings_view.dart';
import '../tools/tools_view.dart';
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
  String? _membershipToken;
  Membership? _membership;
  bool _membershipLoading = false;

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
                GIconButton(
                  icon: Icons.settings_outlined,
                  tooltip: '设置',
                  size: 20,
                  padding: 10,
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
    final settings = context.watch<SettingsController>();
    final name = auth.username ?? '未登录';
    if (_membershipToken != auth.token) {
      _membershipToken = auth.token;
      _membership = null;
      if (auth.token != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _loadMembership(auth.token!);
        });
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      children: [
        _AccountCard(
          name: name,
          avatarUrl: auth.avatarUrl,
          loggedIn: auth.isLoggedIn,
          membershipLoading: _membershipLoading,
          membershipText: _membershipText(),
          membershipActive: _membership?.active == true,
          onAccountTap: auth.isLoggedIn
              ? () => _openPage(context, const AccountSecurityView())
              : () => _openLogin(context),
          onMembershipTap: auth.isLoggedIn
              ? () => _showRedeemDialog(auth.token!)
              : () => _openLogin(context),
        ),
        const _SectionTitle('音乐资料库'),
        _SettingsGroup(
          children: [
            _SettingRow(
              icon: Icons.favorite_rounded,
              title: '喜欢的音乐',
              subtitle: '查看收藏的歌曲',
              onTap: widget.onOpenFavorites ??
                  () => _openSongLibrary(context, favorites: true),
            ),
            _SettingRow(
              icon: Icons.queue_music_rounded,
              title: '我的歌单',
              subtitle: '管理创建和导入的歌单',
              onTap: () => _openPlaylists(
                context,
                filter: UserPlaylistFilter.owned,
              ),
            ),
            _SettingRow(
              icon: Icons.bookmark_rounded,
              title: '收藏的歌单',
              subtitle: '查看收藏的在线歌单',
              onTap: () => _openPlaylists(
                context,
                filter: UserPlaylistFilter.favorites,
              ),
            ),
            _SettingRow(
              icon: Icons.history_rounded,
              title: '播放历史',
              subtitle: '查看完整播放记录',
              onTap: widget.onOpenHistory ??
                  () => _openSongLibrary(context, favorites: false),
            ),
            _SettingRow(
              icon: Icons.download_for_offline_rounded,
              title: '下载管理',
              subtitle: '管理已下载的歌曲',
              onTap: () => _openPage(context, const DownloadsView()),
            ),
          ],
        ),
        const _SectionTitle('外观'),
        _SettingsGroup(
          children: [
            _SettingRow(
              icon: Icons.brightness_6_rounded,
              title: '深浅模式',
              subtitle: '深色、浅色或跟随系统',
              value: const {
                    'system': '跟随系统',
                    'dark': '深色',
                    'light': '浅色',
                  }[settings.themeModeId] ??
                  '跟随系统',
              onTap: () => _pickThemeMode(context, settings),
            ),
            _AccentPaletteRow(
              accentId: settings.accentId,
              onSelected: settings.setAccentColor,
            ),
          ],
        ),
        const _SectionTitle('数据源'),
        _SettingsGroup(
          children: [
            _SettingRow(
              icon: Icons.language_rounded,
              title: '默认音乐源',
              subtitle: '推荐、歌单详情与播放使用；搜索会合并红源、绿源、橙源',
              value: AppConfig.musicSources[settings.source] ?? settings.source,
              onTap: () => _pickSource(context, settings),
            ),
          ],
        ),
        const _SectionTitle('播放与体验'),
        _SettingsGroup(
          children: [
            _SettingRow(
              icon: Icons.graphic_eq_rounded,
              title: '默认播放音质',
              subtitle: '为音乐播放选择合适的音质',
              value:
                  AppConfig.qualityLabels[settings.quality] ?? settings.quality,
              onTap: () => _pickQuality(context, settings),
            ),
            _SettingRow(
              icon: Icons.blur_circular_rounded,
              title: '液态玻璃质量',
              subtitle: '影响导航、播放栏、弹出菜单与设置控件',
              value: const {
                    'smooth': '流畅',
                    'detailed': '精细',
                    'auto': '自动',
                  }[settings.glassQuality] ??
                  '流畅',
              onTap: () => _pickGlassQuality(context, settings),
            ),
            _SettingRow(
              icon: Icons.auto_awesome_rounded,
              title: '减弱动态效果',
              subtitle: '减少封面、歌词和页面过渡动画',
              trailing: SettingsSwitch(
                value: settings.reduceMotion,
                onChanged: settings.setReduceMotion,
              ),
            ),
            _SettingRow(
              icon: Icons.inventory_2_outlined,
              title: '存储与缓存',
              subtitle: '缓存上限、有效期与分类清理',
              onTap: () => _openPage(context, const StorageSettingsView()),
            ),
            if (Theme.of(context).platform == TargetPlatform.macOS ||
                Theme.of(context).platform == TargetPlatform.windows ||
                Theme.of(context).platform == TargetPlatform.linux)
              _SettingRow(
                icon: Icons.desktop_mac_outlined,
                title: '桌面与快捷键',
                subtitle: '状态栏歌词、全局快捷键与窗口控制',
                onTap: () => _openPage(context, const DesktopSettingsView()),
              ),
          ],
        ),
        const _SectionTitle('账户与支持'),
        _SettingsGroup(
          children: [
            _SettingRow(
              icon: Icons.handyman_rounded,
              title: '工具箱',
              subtitle: 'AI 绘画、视频解析与歌单导入',
              onTap: () => _openPage(context, const ToolsView()),
            ),
          ],
        ),
        const _SectionTitle('账户'),
        _SettingsGroup(
          children: [
            _SettingRow(
              icon: Icons.notifications_rounded,
              title: '通知',
              subtitle: '查看服务通知与重要公告',
              onTap: () => _openPage(context, const NotificationsView()),
            ),
            _SettingRow(
              icon: Icons.shield_outlined,
              title: '账号安全',
              subtitle: '登录设备、密码与账号管理',
              onTap: auth.isLoggedIn
                  ? () => _openPage(context, const AccountSecurityView())
                  : () => _openLogin(context),
            ),
            _SettingRow(
              icon: Icons.info_rounded,
              title: '关于 ${AppConfig.appName}',
              subtitle: '版本、更新与服务状态',
              onTap: () => _openPage(context, const AboutView()),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickSource(
    BuildContext context,
    SettingsController settings,
  ) async {
    final value = await showSettingsPicker<String>(
      context,
      title: '选择默认音乐源',
      current: settings.source,
      options: AppConfig.musicSources.entries
          .map((entry) => (value: entry.key, label: entry.value))
          .toList(),
    );
    if (value != null) await settings.setSource(value);
  }

  Future<void> _pickThemeMode(
    BuildContext context,
    SettingsController settings,
  ) async {
    final value = await showSettingsPicker<String>(
      context,
      title: '显示模式',
      current: settings.themeModeId,
      options: const [
        (value: 'system', label: '跟随系统'),
        (value: 'dark', label: '深色'),
        (value: 'light', label: '浅色'),
      ],
    );
    if (value != null) await settings.setThemeMode(value);
  }

  Future<void> _pickQuality(
    BuildContext context,
    SettingsController settings,
  ) async {
    final value = await showSettingsPicker<String>(
      context,
      title: '默认播放音质',
      current: settings.quality,
      options: AppConfig.qualityLabels.entries
          .map((entry) => (value: entry.key, label: entry.value))
          .toList(),
    );
    if (value != null) await settings.setQuality(value);
  }

  Future<void> _pickGlassQuality(
    BuildContext context,
    SettingsController settings,
  ) async {
    final value = await showSettingsPicker<String>(
      context,
      title: '液态玻璃质量',
      current: settings.glassQuality,
      options: const [
        (value: 'smooth', label: '流畅'),
        (value: 'detailed', label: '精细'),
        (value: 'auto', label: '自动'),
      ],
    );
    if (value != null) await settings.setGlassQuality(value);
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

  Future<void> _loadMembership(String token) async {
    if (_membershipLoading) return;
    setState(() => _membershipLoading = true);
    try {
      final membership = await MembershipApi().getMembership(token);
      if (mounted && token == _membershipToken) {
        setState(() => _membership = membership);
      }
    } catch (_) {
      // 会员状态不是页面主体，失败时保留兑换入口即可。
    } finally {
      if (mounted) setState(() => _membershipLoading = false);
    }
  }

  String _membershipText() {
    final membership = _membership;
    if (membership == null || !membership.active) return '尚未开通会员';
    if (membership.lifetime) return '${membership.typeName ?? '永久'} · 长期有效';
    final expiresAt = membership.expiresAt;
    if (expiresAt == null) return membership.typeName ?? '有效会员';
    final date =
        '${expiresAt.year}-${expiresAt.month.toString().padLeft(2, '0')}'
        '-${expiresAt.day.toString().padLeft(2, '0')}';
    return '${membership.typeName ?? '会员'} · 有效期至 $date';
  }

  Future<void> _showRedeemDialog(String token) async {
    final result = await showDialog<RedeemResult>(
      context: context,
      builder: (_) => _RedeemCodeDialog(token: token),
    );
    if (!mounted || result == null) return;
    setState(() => _membership = result.membership);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
  }
}

class _RedeemCodeDialog extends StatefulWidget {
  const _RedeemCodeDialog({required this.token});

  final String token;

  @override
  State<_RedeemCodeDialog> createState() => _RedeemCodeDialogState();
}

class _RedeemCodeDialogState extends State<_RedeemCodeDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _controller.text.trim().toUpperCase().replaceAll(' ', '');
    if (code.isEmpty) {
      setState(() => _error = '请输入兑换码');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await MembershipApi().redeem(code, widget.token);
      if (mounted) Navigator.of(context).pop(result);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('兑换会员卡'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '输入会员兑换码，兑换后即可使用音乐播放等会员功能。',
              style: TextStyle(
                fontSize: 12.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              enabled: !_loading,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\- ]')),
              ],
              decoration: InputDecoration(
                labelText: '兑换码',
                hintText: 'OW-XXXX-XXXX-XXXX-XXXX',
                errorText: _error,
              ),
              onSubmitted: (_) => _loading ? null : _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('立即兑换'),
        ),
      ],
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.name,
    required this.avatarUrl,
    required this.loggedIn,
    required this.membershipLoading,
    required this.membershipText,
    required this.membershipActive,
    required this.onAccountTap,
    required this.onMembershipTap,
  });

  final String name;
  final String? avatarUrl;
  final bool loggedIn;
  final bool membershipLoading;
  final String membershipText;
  final bool membershipActive;
  final VoidCallback onAccountTap;
  final VoidCallback onMembershipTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cardColor = scheme.surfaceContainer.withValues(alpha: 0.92);
    return Container(
      height: 156,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: glassHairline(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          GPressScale(
            onTap: onAccountTap,
            child: SizedBox(
              height: 102,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    UserAvatar(
                      radius: 32,
                      name: name,
                      showInitial: loggedIn,
                      imageUrl: loggedIn ? avatarUrl : null,
                      backgroundColor: membershipActive
                          ? const Color(0xFF5E2B39)
                          : scheme.surfaceContainerHighest,
                      foregroundColor:
                          loggedIn ? Colors.white : scheme.onSurfaceVariant,
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
                              fontSize: 22,
                              height: 1.1,
                              fontWeight: TypeScale.heavy,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            loggedIn ? name : '登录后同步收藏与歌单',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
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
          GPressScale(
            onTap: onMembershipTap,
            child: SizedBox(
              height: 52,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF624936),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: const Color(0xFF98754D)),
                      ),
                      child: const Text(
                        'VIP',
                        style: TextStyle(
                          color: Color(0xFFFFD47A),
                          fontSize: 11,
                          fontWeight: TypeScale.heavy,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: membershipLoading
                          ? Text(
                              '正在读取会员状态',
                              style: TextStyle(
                                fontSize: 13,
                                color: scheme.onSurfaceVariant,
                              ),
                            )
                          : Text(
                              loggedIn ? membershipText : '登录后开通会员',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: TypeScale.semibold,
                              ),
                            ),
                    ),
                    Text(
                      loggedIn ? '兑换码' : '登录',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
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
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 10, 0),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                '我的',
                style: TextStyle(fontSize: 17, fontWeight: TypeScale.bold),
              ),
            ),
            GIconButton(
              icon: Icons.settings_outlined,
              tooltip: '设置',
              size: 20,
              padding: 10,
              onTap: onSettings,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: TypeScale.bold,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: glassHairline(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 58),
                child: Divider(height: 1, color: glassHairline(context)),
              ),
          ],
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GPressScale(
      onTap: onTap,
      child: SizedBox(
        height: 64,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Icon(icon, size: 19, color: scheme.onSurface),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: TypeScale.semibold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: 12),
                Container(
                  constraints: const BoxConstraints(minWidth: 48),
                  child: Text(
                    value!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: TypeScale.medium,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ] else if (onTap != null) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AccentPaletteRow extends StatelessWidget {
  const _AccentPaletteRow({required this.accentId, required this.onSelected});

  final String accentId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 116,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            const SizedBox(width: 40),
            const Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('主题色',
                      style: TextStyle(
                          fontSize: 14.5, fontWeight: TypeScale.semibold)),
                  SizedBox(height: 3),
                  Text('强调色与背景氛围随之变化',
                      style:
                          TextStyle(fontSize: 11.5, color: Color(0xFF929A95))),
                ],
              ),
            ),
            Text(
              AppAccent.byId(accentId).name,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 12),
            Wrap(
              spacing: 8,
              children: AppAccent.all.map((accent) {
                final selected = accent.id == accentId;
                return GPressScale(
                  onTap: () => onSelected(accent.id),
                  child: Container(
                    width: selected ? 30 : 25,
                    height: selected ? 30 : 25,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.color,
                      border: selected
                          ? Border.all(color: Colors.white, width: 2)
                          : null,
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                  color: accent.color.withValues(alpha: 0.35),
                                  blurRadius: 0,
                                  spreadRadius: 2)
                            ]
                          : null,
                    ),
                    child: selected
                        ? const Icon(Icons.check_rounded,
                            color: Colors.white, size: 19)
                        : null,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
