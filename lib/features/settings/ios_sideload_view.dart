import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/ios_sideload.dart';
import '../../core/services/ios_sideload_service.dart';
import '../../widgets/glass.dart';
import 'settings_components.dart';

class IosSideloadView extends StatefulWidget {
  const IosSideloadView({super.key});

  @override
  State<IosSideloadView> createState() => _IosSideloadViewState();
}

class _IosSideloadViewState extends State<IosSideloadView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
  }

  Future<void> _load() async {
    final service = context.read<IosSideloadService>();
    try {
      await service.loadManifest();
      await service.refreshStatus();
    } on IosSideloadException {
      // The service publishes a structured diagnostic for the page to render.
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<IosSideloadService>();
    final manifest = service.manifest;
    final status = service.status;
    final canRun = service.taskState != IosSideloadTaskState.installing &&
        service.taskState != IosSideloadTaskState.refreshing;

    return Scaffold(
      appBar: GAppBar(
        title: 'iOS 安装中心',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
        children: [
          _IntroNotice(
              platformSupported: Platform.isMacOS || Platform.isWindows),
          const SettingsSection('ECS 版本'),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.system_update_alt_rounded,
                title: '最新构建',
                subtitle: manifest == null
                    ? _diagnostic(status)
                    : '已通过 SHA-256 校验，可交给本机签名助手',
                value: manifest == null
                    ? null
                    : '${manifest.version} (${manifest.buildNumber})',
                onTap: () => unawaited(_load()),
              ),
              if (manifest != null)
                SettingsRow(
                  icon: Icons.fingerprint_rounded,
                  title: '构建校验值',
                  subtitle: manifest.sha256,
                  value: manifest.minimumOsVersion == null
                      ? null
                      : 'iOS ${manifest.minimumOsVersion}+',
                ),
            ],
          ),
          const SettingsSection('本机签名状态'),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.account_circle_outlined,
                title: 'Apple 账号',
                subtitle: status.accountLabel == null
                    ? '账号只保存在本机钥匙串，不会上传到 ECS'
                    : '凭据由本机签名助手管理',
                value: status.accountLabel ?? '未配置',
              ),
              SettingsRow(
                icon: Icons.phone_iphone_rounded,
                title: '设备',
                subtitle: _deviceSubtitle(status),
                value: status.devices.isEmpty
                    ? '未发现'
                    : '${status.devices.length} 台',
              ),
              SettingsRow(
                icon: Icons.schedule_rounded,
                title: '签名有效期',
                subtitle: status.signatureExpiresAt == null
                    ? '安装后由本机助手回报预计到期时间'
                    : '剩余 ${_remaining(status.signatureExpiresAt!)}',
                value: status.signatureExpiresAt == null
                    ? '未知'
                    : _dateLabel(status.signatureExpiresAt!),
              ),
            ],
          ),
          const SettingsSection('操作'),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.download_rounded,
                title: '安装最新版本',
                subtitle: canRun ? '下载并交给本机助手签名安装' : '任务执行中，请等待当前操作完成',
                trailing: FilledButton.icon(
                  onPressed: manifest == null || !canRun
                      ? null
                      : () => unawaited(service.installLatest()),
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: const Text('安装'),
                ),
              ),
              SettingsRow(
                icon: Icons.autorenew_rounded,
                title: '刷新当前签名',
                subtitle: canRun ? '在过期前重新安装，避免 App 无法启动' : '任务执行中，请等待当前操作完成',
                trailing: FilledButton.icon(
                  onPressed: !canRun
                      ? null
                      : () => unawaited(service.refreshInstalled()),
                  icon: const Icon(Icons.autorenew_rounded, size: 16),
                  label: const Text('刷新'),
                ),
              ),
            ],
          ),
          if (status.errorCode != null) ...[
            const SettingsSection('诊断'),
            SettingsGroup(
              children: [
                SettingsRow(
                  icon: Icons.warning_amber_rounded,
                  title: _errorTitle(status.errorCode!),
                  subtitle: status.message ?? '请检查本机签名助手、设备连接和 Apple 账号状态',
                  value: '需要处理',
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _diagnostic(IosSideloadStatus status) {
    if (status.message != null) return status.message!;
    if (status.errorCode == null) return '正在读取 ECS 清单';
    return _errorTitle(status.errorCode!);
  }

  String _deviceSubtitle(IosSideloadStatus status) {
    if (status.devices.isEmpty) return '请连接并信任 iPhone';
    final connectedDevices =
        status.devices.where((device) => device.connected).toList();
    final connected = connectedDevices.length;
    if (connected == 0) return '已登记但当前不在线';
    if (connected == 1) return '${connectedDevices.first.name} 在线';
    return '$connected 台设备在线';
  }

  String _remaining(DateTime expiry) {
    final difference = expiry.difference(DateTime.now().toUtc());
    if (difference.isNegative) return '已过期';
    final hours = difference.inHours;
    if (hours < 24) return '$hours 小时';
    return '${difference.inDays} 天';
  }

  String _dateLabel(DateTime value) {
    final local = value.toLocal();
    return '${local.month}/${local.day} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _errorTitle(IosSideloadErrorCode code) => switch (code) {
        IosSideloadErrorCode.notConfigured => 'ECS 清单未配置',
        IosSideloadErrorCode.helperMissing => '本地签名助手缺失',
        IosSideloadErrorCode.xcodeMissing => 'macOS 工具链缺失',
        IosSideloadErrorCode.appleDevicesMissing => 'Apple 设备组件缺失',
        IosSideloadErrorCode.deviceUntrusted => '设备尚未信任',
        IosSideloadErrorCode.developerModeRequired => '需要打开开发者模式',
        IosSideloadErrorCode.profileExpired => '签名已过期',
        IosSideloadErrorCode.installFailed => '安装失败',
        IosSideloadErrorCode.network => '网络或 ECS 访问失败',
        IosSideloadErrorCode.invalidManifest => 'ECS 清单或 IPA 校验失败',
        IosSideloadErrorCode.busy => '已有任务正在执行',
        IosSideloadErrorCode.cancelled => '任务已取消',
        IosSideloadErrorCode.unknown => '本地助手报告未知错误',
      };
}

class _IntroNotice extends StatelessWidget {
  const _IntroNotice({required this.platformSupported});

  final bool platformSupported;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: glassHairline(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              platformSupported
                  ? '桌面端负责本机签名和续签，ECS 不会接收 Apple ID 或私钥。免费个人签名仍受 Apple 的有效期和设备限制。'
                  : 'iOS 安装中心只支持 macOS 和 Windows 桌面端。',
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
