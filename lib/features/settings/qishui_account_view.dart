import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/api/qishui_api.dart';
import '../../widgets/async_cover.dart';
import '../../widgets/glass.dart';
import '../profile/login_view.dart';
import 'qishui_account_controller.dart';

class QishuiAccountView extends StatefulWidget {
  const QishuiAccountView({super.key, this.api});
  final QishuiApi? api;
  @override
  State<QishuiAccountView> createState() => _QishuiAccountViewState();
}

class _QishuiAccountViewState extends State<QishuiAccountView>
    with WidgetsBindingObserver {
  late final QishuiAccountController _controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = QishuiAccountController(
        auth: context.read<AuthController>(), api: widget.api)
      ..load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _controller.setActive(state == AppLifecycleState.resumed);
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openDouyin() async {
    final uri = Uri.tryParse(_controller.qr?.qrcodeUrl ?? '');
    if (uri == null || uri.scheme != 'aweme') return;
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('未能打开抖音，请使用抖音扫描二维码')));
    }
  }

  Future<void> _unbind() async {
    final auth = context.read<AuthController>();
    final generation = auth.sessionGeneration;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('解除黑源绑定？'),
                content: const Text('删除本应用保存的绑定。此操作不会撤销抖音侧的授权。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('解除绑定'))
                ]));
    if (confirmed == true &&
        mounted &&
        auth.sessionGeneration == generation &&
        auth.isLoggedIn) {
      await _controller.unbind();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
        appBar: GAppBar(
            title: '黑源账号', onBack: () => Navigator.of(context).maybePop()),
        body: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final c = _controller;
              final account = c.account;
              final qr = c.qr;
              final bytes = qr?.qrBytes;
              return Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                          children: [
                            GSurface(
                                padding: const EdgeInsets.all(22),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('汽水音乐 · 黑源',
                                          style: TextStyle(
                                              fontSize: 24,
                                              fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 12),
                                      Text('搜索歌曲与歌单，收藏后可在手机和车机中访问。',
                                          style: TextStyle(
                                              color: scheme.onSurfaceVariant,
                                              height: 1.6)),
                                      const SizedBox(height: 8),
                                      Text(
                                          '使用抖音扫码绑定汽水账号。绑定后可使用个人音乐漫游；授权过期时可刷新或重新扫码。',
                                          style: TextStyle(
                                              color: scheme.onSurfaceVariant,
                                              height: 1.6)),
                                    ])),
                            const SizedBox(height: 16),
                            if (!auth.isLoggedIn)
                              GButton(
                                  label: '登录后绑定',
                                  icon: Icons.login,
                                  onTap: () => Navigator.of(context).push(
                                      buildAppRoute(
                                          context, (_) => const LoginView())))
                            else
                              GSurface(
                                  padding: const EdgeInsets.all(22),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (account != null) ...[
                                          Row(children: [
                                            AsyncCover(
                                                url: account.avatarUrl,
                                                size: 52,
                                                radius: 26),
                                            const SizedBox(width: 14),
                                            Expanded(
                                                child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                  Text(
                                                      account.nickname ??
                                                          (account.bound
                                                              ? '已绑定账号'
                                                              : '尚未绑定'),
                                                      style: const TextStyle(
                                                          fontSize: 18,
                                                          fontWeight:
                                                              FontWeight.w600)),
                                                  Text(
                                                      account.status ==
                                                              'expired'
                                                          ? '授权已过期'
                                                          : account.bound
                                                              ? (account.vip
                                                                  ? '已绑定 · 汽水会员'
                                                                  : '已绑定')
                                                              : '使用抖音扫码授权',
                                                      style: TextStyle(
                                                          color: scheme
                                                              .onSurfaceVariant)),
                                                ]))
                                          ]),
                                          if (account.expiresAt != null)
                                            Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 12),
                                                child: Text(
                                                    '授权有效期：${account.expiresAt!.toLocal().toString().split('.').first}',
                                                    style: TextStyle(
                                                        color: scheme
                                                            .onSurfaceVariant,
                                                        fontSize: 12))),
                                          const SizedBox(height: 20),
                                        ],
                                        if (bytes != null) ...[
                                          Center(
                                              child: Container(
                                                  color: Colors.white,
                                                  padding:
                                                      const EdgeInsets.all(16),
                                                  child: Image.memory(bytes,
                                                      width: 220,
                                                      height: 220,
                                                      fit: BoxFit.contain,
                                                      errorBuilder: (_, __,
                                                              ___) =>
                                                          const SizedBox(
                                                              width: 220,
                                                              height: 100,
                                                              child: Center(
                                                                  child: Text(
                                                                      '二维码加载失败，请重新获取',
                                                                      style: TextStyle(
                                                                          color:
                                                                              Colors.black))))))),
                                          const SizedBox(height: 14),
                                          Text(
                                              qr!.status == 'scanned'
                                                  ? '已扫码，请在抖音中确认'
                                                  : '请使用抖音扫描二维码',
                                              textAlign: TextAlign.center),
                                          if (Uri.tryParse(qr.qrcodeUrl ?? '')
                                                  ?.scheme ==
                                              'aweme')
                                            TextButton(
                                                onPressed: _openDouyin,
                                                child: const Text('在本机抖音中打开')),
                                          TextButton(
                                              onPressed: c.cancelQr,
                                              child: const Text('取消扫码')),
                                        ] else
                                          GButton(
                                              label: c.busy
                                                  ? '处理中…'
                                                  : account?.bound == true
                                                      ? '重新扫码绑定'
                                                      : '获取授权二维码',
                                              icon: Icons.qr_code_rounded,
                                              loading: c.busy,
                                              onTap: c.busy ? null : c.start,
                                              expand: true),
                                        if (account?.bound == true &&
                                            qr == null) ...[
                                          const SizedBox(height: 10),
                                          OutlinedButton(
                                              onPressed:
                                                  c.busy ? null : c.refresh,
                                              child: const Text('刷新授权')),
                                          TextButton(
                                              onPressed:
                                                  c.busy ? null : _unbind,
                                              child: const Text('解除绑定')),
                                        ],
                                        if (c.error != null)
                                          Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 14),
                                              child: Text(c.error!,
                                                  style: TextStyle(
                                                      color: scheme.error,
                                                      height: 1.5))),
                                        if (c.account == null &&
                                            c.error != null)
                                          TextButton(
                                              onPressed: c.busy ? null : c.load,
                                              child: const Text('重新读取状态')),
                                      ])),
                          ])));
            }));
  }
}
