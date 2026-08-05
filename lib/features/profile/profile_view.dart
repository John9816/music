import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api/membership_api.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/config/app_config.dart';
import '../../core/models/membership.dart';
import '../../core/services/cache_service.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/glass.dart';
import '../settings/about_view.dart';
import '../settings/account_security_view.dart';
import '../settings/desktop_settings_view.dart';
import '../settings/notifications_view.dart';
import '../settings/storage_settings_view.dart';
import '../tools/tools_view.dart';
import 'login_view.dart';

/// 个人中心。嵌入主框架时保留侧栏和全局播放栏。
class ProfileView extends StatefulWidget {
  const ProfileView({
    super.key,
    this.embedded = false,
    this.onBack,
  });

  final bool embedded;
  final VoidCallback? onBack;

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  int _cacheBytes = -1;
  String? _membershipToken;
  Membership? _membership;
  bool _membershipLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
  }

  Future<void> _loadCacheSize() async {
    try {
      final bytes = await CacheService.instance.totalSizeBytes();
      if (mounted) setState(() => _cacheBytes = bytes);
    } catch (_) {
      if (mounted) setState(() => _cacheBytes = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = ColoredBox(
      color: _profileBackground(context),
      child: Column(
        children: [
          if (widget.embedded)
            _ProfileHeader(onBack: widget.onBack)
          else
            GAppBar(
              title: '个人中心',
              onBack: () => Navigator.of(context).maybePop(),
              transparent: true,
            ),
          Expanded(child: _buildContent(context)),
        ],
      ),
    );
    return widget.embedded
        ? ColoredBox(color: Colors.transparent, child: content)
        : Scaffold(body: content);
  }

  Widget _buildContent(BuildContext context) {
    final auth = context.watch<AuthController>();
    final settings = context.watch<SettingsController>();
    final selectedAccent = AppAccent.all.indexWhere(
      (accent) => accent.id == settings.accentId,
    );
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
              valuePill: true,
              onTap: () => _pickTheme(context, settings),
            ),
            _ThemeColorRow(
              selectedIndex: selectedAccent < 0 ? 2 : selectedAccent,
              onSelected: (index) => _selectAccent(index, settings),
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
              valuePill: true,
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
              valuePill: true,
              onTap: () => _pickGlassQuality(settings),
            ),
            _SettingRow(
              icon: Icons.auto_awesome_rounded,
              title: '减弱动态效果',
              subtitle: '减少封面、歌词和页面过渡动画',
              trailing: _CompactSwitch(
                value: settings.reduceMotion,
                onChanged: settings.setReduceMotion,
              ),
            ),
            _SettingRow(
              icon: Icons.inventory_2_outlined,
              title: '存储与缓存',
              subtitle: _cacheBytes < 0
                  ? '正在计算缓存占用'
                  : '缓存上限、有效期与分类清理 · ${CacheService.formatBytes(_cacheBytes)}',
              onTap: () async {
                await _openPage(context, const StorageSettingsView());
                _loadCacheSize();
              },
            ),
            _SettingRow(
              icon: Icons.desktop_mac_outlined,
              title: '桌面与快捷键',
              subtitle: '状态栏歌词、全局快捷键与窗口控制',
              onTap: () => _openPage(context, const DesktopSettingsView()),
            ),
          ],
        ),
        const _SectionTitle('工具与服务'),
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
        const _SectionTitle('账户与支持'),
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
              value: auth.isLoggedIn ? null : '登录 / 注册',
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

  Color _profileBackground(BuildContext context) {
    return Theme.of(context).colorScheme.surfaceContainerLowest;
  }

  void _openLogin(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginView()),
    );
  }

  Future<void> _openPage(BuildContext context, Widget page) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  Future<void> _pickGlassQuality(SettingsController settings) async {
    final value = await _pick<String>(
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

  void _selectAccent(int index, SettingsController settings) {
    settings.setAccentColor(AppAccent.all[index].id);
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

  Future<void> _pickTheme(
    BuildContext context,
    SettingsController settings,
  ) async {
    final value = await _pick<String>(
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
    final value = await _pick<String>(
      context,
      title: '默认播放音质',
      current: settings.quality,
      options: AppConfig.qualityLabels.entries
          .map((e) => (value: e.key, label: e.value))
          .toList(),
    );
    if (value != null) await settings.setQuality(value);
  }

  Future<T?> _pick<T>(
    BuildContext context, {
    required String title,
    required T current,
    required List<({T value, String label})> options,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: TypeScale.bold,
                ),
              ),
            ),
            for (final option in options)
              GListTile(
                selected: option.value == current,
                title: Text(option.label),
                trailing: option.value == current
                    ? const Icon(Icons.check_rounded, size: 19)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(option.value),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
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
    required this.loggedIn,
    required this.membershipLoading,
    required this.membershipText,
    required this.membershipActive,
    required this.onAccountTap,
    required this.onMembershipTap,
  });

  final String name;
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
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: membershipActive
                          ? const Color(0xFF5E2B39)
                          : scheme.surfaceContainerHighest,
                      child: loggedIn && name.isNotEmpty
                          ? Text(
                              name.characters.first.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: TypeScale.heavy,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              Icons.person_rounded,
                              size: 28,
                              color: scheme.onSurfaceVariant,
                            ),
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
  const _ProfileHeader({this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          const SizedBox(width: 10),
          GIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            tooltip: '返回',
            size: 20,
            padding: 10,
            backgroundColor: Colors.transparent,
            onTap: onBack,
          ),
          const SizedBox(width: 8),
          const Text(
            '个人中心',
            style: TextStyle(fontSize: 17, fontWeight: TypeScale.bold),
          ),
        ],
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
    this.valuePill = false,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? value;
  final bool valuePill;
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
              if (trailing != null) ...[
                const SizedBox(width: 12),
                trailing!,
              ] else if (value != null) ...[
                const SizedBox(width: 12),
                Container(
                  constraints: const BoxConstraints(minWidth: 48),
                  padding: valuePill
                      ? const EdgeInsets.symmetric(horizontal: 14, vertical: 8)
                      : EdgeInsets.zero,
                  decoration: valuePill
                      ? BoxDecoration(
                          color: glassFill(context, alpha: 0.08),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: scheme.outlineVariant),
                        )
                      : null,
                  child: Text(
                    value!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          valuePill ? TypeScale.semibold : TypeScale.medium,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
              if (onTap != null && trailing == null && !valuePill) ...[
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

class _ThemeColorRow extends StatelessWidget {
  const _ThemeColorRow({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const colors = [
    Color(0xFFFF375F),
    Color(0xFFFF9F0A),
    Color(0xFF30D158),
    Color(0xFF40C8E0),
    Color(0xFF0A84FF),
    Color(0xFFBF5AF2),
    Color(0xFFFF6482),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 110,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 24,
                  child: Icon(Icons.stars_rounded, size: 19),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '主题色',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: TypeScale.semibold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '强调色与背景氛围随之变化',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  const [
                    '律动红',
                    '落日橙',
                    '森林绿',
                    '湖水青',
                    '天际蓝',
                    '幻夜紫',
                    '蔷薇粉',
                  ][selectedIndex],
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                const SizedBox(width: 40),
                for (var index = 0; index < colors.length; index++) ...[
                  GPressScale(
                    onTap: () => onSelected(index),
                    child: Container(
                      width: 29,
                      height: 29,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selectedIndex == index
                              ? scheme.onSurface
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors[index],
                        ),
                        child: selectedIndex == index
                            ? const Icon(
                                Icons.check_rounded,
                                size: 15,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ),
                  ),
                  if (index != colors.length - 1) const SizedBox(width: 9),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactSwitch extends StatelessWidget {
  const _CompactSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      toggled: value,
      button: true,
      child: GPressScale(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          width: 46,
          height: 26,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: value
                ? scheme.primary
                : scheme.onSurfaceVariant.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(14),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
