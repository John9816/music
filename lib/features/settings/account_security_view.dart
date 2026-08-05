import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/auth_api.dart';
import '../../core/auth/auth_controller.dart';
import '../../widgets/glass.dart';
import 'settings_components.dart';

class AccountSecurityView extends StatefulWidget {
  const AccountSecurityView({super.key});

  @override
  State<AccountSecurityView> createState() => _AccountSecurityViewState();
}

class _AccountSecurityViewState extends State<AccountSecurityView> {
  final AuthApi _api = AuthApi();
  Future<List<Map<String, dynamic>>>? _devices;
  bool _resettingPassword = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _devices ??= _loadDevices();
  }

  Future<List<Map<String, dynamic>>> _loadDevices() {
    final token = context.read<AuthController>().token;
    if (token == null) return Future.value(const []);
    return _api.getDevices(token);
  }

  void _refreshDevices() => setState(() => _devices = _loadDevices());

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    if (!auth.isLoggedIn) {
      return Scaffold(
        appBar: GAppBar(
          title: '账号安全',
          onBack: () => Navigator.of(context).maybePop(),
        ),
        body: const GEmptyState(
          icon: Icons.lock_outline_rounded,
          title: '尚未登录',
          text: '登录后可管理密码、登录设备和账号',
        ),
      );
    }
    return Scaffold(
      appBar: GAppBar(
        title: '账号安全',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              auth.username ?? '已登录账号',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SettingsSection('登录安全'),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.lock_reset_rounded,
                title: '重置密码',
                subtitle: '向当前账号邮箱发送安全重置链接',
                trailing: _resettingPassword
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                onTap: _resettingPassword ? null : () => _resetPassword(auth),
              ),
            ],
          ),
          const SettingsSection('登录设备'),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _devices,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SettingsGroup(
                  children: [
                    SettingsRow(
                      icon: Icons.devices_rounded,
                      title: '正在读取登录设备',
                    ),
                  ],
                );
              }
              if (snapshot.hasError) {
                return SettingsGroup(
                  children: [
                    SettingsRow(
                      icon: Icons.sync_problem_rounded,
                      title: '设备列表加载失败',
                      subtitle: snapshot.error.toString(),
                      value: '重试',
                      onTap: _refreshDevices,
                    ),
                  ],
                );
              }
              final devices = snapshot.data ?? const [];
              if (devices.isEmpty) {
                return const SettingsGroup(
                  children: [
                    SettingsRow(
                      icon: Icons.devices_rounded,
                      title: '暂无可管理的设备记录',
                      subtitle: '当前服务未返回登录设备信息',
                    ),
                  ],
                );
              }
              return SettingsGroup(
                children: [
                  for (final device in devices) _deviceRow(device, auth.token!),
                ],
              );
            },
          ),
          const SettingsSection('账号管理'),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.logout_rounded,
                title: '退出登录',
                destructive: true,
                onTap: () => _logout(auth),
              ),
              SettingsRow(
                icon: Icons.delete_forever_outlined,
                title: '注销账号',
                subtitle: '注销后所有设备都会退出，账号数据不可恢复',
                destructive: true,
                onTap: () => _deleteAccount(auth),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _deviceRow(Map<String, dynamic> device, String token) {
    final id = (device['id'] ?? device['deviceId'] ?? '').toString();
    final name =
        (device['name'] ?? device['deviceName'] ?? device['model'] ?? '未知设备')
            .toString();
    final platform = (device['platform'] ?? device['os'] ?? '').toString();
    final lastActive = (device['lastActiveAt'] ??
            device['lastSeenAt'] ??
            device['updatedAt'] ??
            '')
        .toString();
    final current = device['current'] == true || device['isCurrent'] == true;
    return SettingsRow(
      icon: platform.toLowerCase().contains('android') ||
              platform.toLowerCase().contains('ios')
          ? Icons.phone_android_rounded
          : Icons.computer_rounded,
      title: name,
      subtitle: current
          ? '当前设备${lastActive.isEmpty ? '' : ' · 最近活跃 $lastActive'}'
          : lastActive.isEmpty
              ? platform
              : '最近活跃 $lastActive',
      trailing: current || id.isEmpty
          ? null
          : GIconButton(
              icon: Icons.delete_outline_rounded,
              tooltip: '移除此设备',
              tint: Theme.of(context).colorScheme.error,
              size: 18,
              padding: 7,
              onTap: () => _revokeDevice(id, name, token),
            ),
    );
  }

  Future<void> _resetPassword(AuthController auth) async {
    final account = auth.username;
    final token = auth.token;
    if (account == null || token == null) return;
    setState(() => _resettingPassword = true);
    try {
      final message = await _api.requestPasswordReset(account, token);
      _message(message);
    } catch (error) {
      _message(error.toString());
    } finally {
      if (mounted) setState(() => _resettingPassword = false);
    }
  }

  Future<void> _revokeDevice(String id, String name, String token) async {
    if (!await _confirm('移除登录设备？', '$name 将需要重新登录。')) return;
    try {
      await _api.revokeDevice(id, token);
      _refreshDevices();
      _message('设备已移除');
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _logout(AuthController auth) async {
    if (!await _confirm('退出登录？', '本机登录状态将被清除。')) return;
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    await auth.logout();
  }

  Future<void> _deleteAccount(AuthController auth) async {
    final controller = TextEditingController();
    final account = auth.username ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('注销账号'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('该操作不可恢复。请输入当前账号以确认：'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(hintText: account),
                onChanged: (_) => setDialogState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: controller.text.trim() == account
                  ? () => Navigator.of(dialogContext).pop(true)
                  : null,
              child: const Text('永久注销'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (confirmed != true || auth.token == null) return;
    try {
      await _api.deleteAccount(auth.token!);
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      await auth.logout();
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<bool> _confirm(String title, String content) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(content),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('确认'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}
