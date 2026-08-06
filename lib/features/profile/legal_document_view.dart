import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../widgets/glass.dart';

enum LegalDocumentType { agreement, privacy }

class LegalDocumentView extends StatelessWidget {
  const LegalDocumentView({super.key, required this.type});

  final LegalDocumentType type;

  @override
  Widget build(BuildContext context) {
    final agreement = type == LegalDocumentType.agreement;
    final title = agreement ? '用户协议' : '隐私政策';
    final sections = agreement ? _agreementSections : _privacySections;
    return Scaffold(
      appBar: GAppBar(
        title: title,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 48),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$title · ${AppConfig.appName}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: TypeScale.heavy,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '更新日期：2026 年 8 月 5 日',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 26),
                  for (final section in sections) ...[
                    Text(
                      section.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: TypeScale.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      section.body,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.7,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 22),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

typedef _LegalSection = ({String title, String body});

const _agreementSections = <_LegalSection>[
  (
    title: '一、服务说明',
    body: '${AppConfig.appName} 提供音乐检索、播放、收藏、歌单、播放记录和相关辅助功能。'
        '音乐内容及可用性可能由第三方服务决定，实际功能以客户端当前提供为准。',
  ),
  (
    title: '二、账号与安全',
    body: '你应使用真实可用的邮箱注册，并妥善保管密码和登录设备。不得转让账号、冒用他人身份，'
        '或利用自动化方式批量创建账号。发现异常登录时，请及时重置密码并移除未知设备。',
  ),
  (
    title: '三、使用规范',
    body: '不得利用本服务实施违法活动、攻击服务、绕过访问控制、干扰其他用户，或传播侵权及有害内容。'
        '对违反规则的行为，我们可以限制相关功能并保留必要的安全记录。',
  ),
  (
    title: '四、内容与知识产权',
    body: '客户端界面、代码、品牌元素及服务内容受相应知识产权保护。音乐作品的权利归其权利人所有，'
        '你应仅在法律和内容提供方许可的范围内使用。',
  ),
  (
    title: '五、服务变更与责任边界',
    body: '因网络、设备、第三方接口维护或不可抗力导致的暂时不可用，我们会尽力恢复。'
        '对于超出合理控制范围的间接损失，依法不承担超出适用法律要求的责任。',
  ),
  (
    title: '六、协议更新',
    body: '功能或法律要求变化时，本协议可能更新。重要变化会通过客户端通知；继续使用服务表示你接受更新后的条款。',
  ),
];

const _privacySections = <_LegalSection>[
  (
    title: '一、我们处理的信息',
    body: '注册和账号管理需要昵称、邮箱及加密后的身份凭据；同步功能会处理收藏、歌单和播放记录；'
        '为保障登录安全，我们可能记录设备类型、系统版本、登录时间和必要的网络信息。',
  ),
  (
    title: '二、信息的使用目的',
    body: '上述信息用于登录验证、跨设备同步、找回密码、播放服务、故障诊断、安全防护和向你展示重要服务通知。'
        '我们不会将信息用于与这些目的无关的自动化决策。',
  ),
  (
    title: '三、本地存储与缓存',
    body: '登录令牌和偏好设置保存在本机，用于保持登录和恢复设置；歌曲、图片、歌词等缓存可在“存储与缓存”中查看和清理。'
        '主动退出登录后，本机会清除账号会话信息。',
  ),
  (
    title: '四、共享与第三方服务',
    body: '为完成音乐检索、播放、封面加载和更新检查，客户端会向相关服务发送完成请求所必需的信息。'
        '除法律要求、保护安全或提供你主动请求的功能外，不会出售你的个人信息。',
  ),
  (
    title: '五、你的权利',
    body: '你可以查看和清理缓存、管理登录设备、重置密码、退出登录，并在账号安全页面申请注销账号。'
        '账号注销后，相关数据将按法律要求删除或匿名化处理。',
  ),
  (
    title: '六、数据安全与更新',
    body: '我们采取访问控制、传输保护和最小化处理等措施保护信息。隐私政策发生重要变化时会通过客户端通知。',
  ),
];
