import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/auth_api.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/config/app_config.dart';
import '../../widgets/glass.dart';
import 'legal_document_view.dart';

/// 柒伍壹壹音乐的账号入口。
class LoginView extends StatefulWidget {
  const LoginView({super.key, this.allowBack = true});

  final bool allowBack;

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _account = TextEditingController();
  final _password = TextEditingController();
  bool _obscurePassword = true;
  bool _agreed = false;

  @override
  void dispose() {
    _account.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final account = _account.text.trim();
    if (account.isEmpty || _password.text.isEmpty) {
      _message('请输入邮箱或账号和密码');
      return;
    }
    if (!_agreed) {
      _message('请先阅读并同意用户协议与隐私政策');
      return;
    }
    final auth = context.read<AuthController>();
    final ok = await auth.login(account, _password.text);
    if (!mounted) return;
    if (ok) {
      if (widget.allowBack) Navigator.of(context).maybePop();
    } else {
      _message(auth.error ?? '登录失败，请稍后重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    return _AuthPage(
      onBack: widget.allowBack ? () => Navigator.of(context).maybePop() : null,
      showBrand: true,
      title: '继续聆听',
      children: [
        _AuthField(
          controller: _account,
          hintText: '邮箱',
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username, AutofillHints.email],
        ),
        const SizedBox(height: 14),
        _AuthField(
          controller: _password,
          hintText: '密码',
          obscureText: _obscurePassword,
          autofillHints: const [AutofillHints.password],
          onSubmitted: (_) => _submit(),
          suffix: GIconButton(
            icon: _obscurePassword
                ? Icons.visibility_off_rounded
                : Icons.visibility_rounded,
            tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
            size: 20,
            padding: 9,
            backgroundColor: Colors.transparent,
            onTap: () => setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Checkbox(
              value: _agreed,
              onChanged: (value) => setState(() => _agreed = value ?? false),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _agreed = !_agreed),
                child: Text(
                  '已阅读并同意用户协议与隐私政策',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            _AuthTextButton(
              label: '忘记密码',
              onTap: () => _open(const ForgotPasswordView()),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 36),
          child: Row(
            children: [
              _AuthLink(
                label: '查看用户协议',
                onTap: () => _open(
                  const LegalDocumentView(type: LegalDocumentType.agreement),
                ),
              ),
              const SizedBox(width: 20),
              _AuthLink(
                label: '查看隐私政策',
                onTap: () => _open(
                  const LegalDocumentView(type: LegalDocumentType.privacy),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        _AuthPrimaryButton(
          label: '登录',
          loading: auth.loading,
          onTap: auth.loading ? null : _submit,
        ),
        const SizedBox(height: 16),
        Center(
          child: _AuthTextButton(
            label: '创建账号',
            onTap: () => _open(const RegisterView()),
          ),
        ),
      ],
    );
  }

  void _open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class RegisterView extends StatefulWidget {
  const RegisterView({super.key});

  @override
  State<RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<RegisterView> {
  final _nickname = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nickname.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final nickname = _nickname.text.trim();
    final email = _email.text.trim();
    final password = _password.text;
    if (nickname.isEmpty || email.isEmpty || password.isEmpty) {
      _message('请完整填写昵称、邮箱和密码');
      return;
    }
    if (!_looksLikeEmail(email)) {
      _message('请输入有效的邮箱地址');
      return;
    }
    if (password.length < 6) {
      _message('密码至少需要 6 位');
      return;
    }
    final auth = context.read<AuthController>();
    final ok = await auth.register(nickname, email, password);
    if (!mounted) return;
    if (!ok) {
      _message(auth.error ?? '创建账号失败，请稍后重试');
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    return _AuthPage(
      onBack: () => Navigator.of(context).maybePop(),
      title: '创建账号',
      subtitle: '注册后前往邮箱完成验证，即可开始体验会员',
      children: [
        _AuthField(
          controller: _nickname,
          hintText: '昵称',
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newUsername],
        ),
        const SizedBox(height: 14),
        _AuthField(
          controller: _email,
          hintText: '邮箱',
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
        ),
        const SizedBox(height: 14),
        _AuthField(
          controller: _password,
          hintText: '密码',
          obscureText: _obscurePassword,
          autofillHints: const [AutofillHints.newPassword],
          onSubmitted: (_) => _submit(),
          suffix: GIconButton(
            icon: _obscurePassword
                ? Icons.visibility_off_rounded
                : Icons.visibility_rounded,
            tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
            size: 20,
            padding: 9,
            backgroundColor: Colors.transparent,
            onTap: () => setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
          child: Text(
            '建议混合字母、数字和符号',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 24),
        _AuthPrimaryButton(
          label: '创建账号',
          loading: auth.loading,
          onTap: auth.loading ? null : _submit,
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '已经有账号？',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            _AuthTextButton(
              label: '去登录',
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
      ],
    );
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class ForgotPasswordView extends StatefulWidget {
  const ForgotPasswordView({super.key, this.api});

  final AuthApi? api;

  @override
  State<ForgotPasswordView> createState() => _ForgotPasswordViewState();
}

class _ForgotPasswordViewState extends State<ForgotPasswordView> {
  final _email = TextEditingController();
  final _verificationCode = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  late final AuthApi _api = widget.api ?? AuthApi();
  bool _sending = false;
  bool _resetting = false;
  bool _obscurePassword = true;
  int _resendSeconds = 0;
  Timer? _resendTimer;
  String? _codeEmail;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _email.dispose();
    _verificationCode.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _email.text.trim();
    if (!_looksLikePasswordResetEmail(email)) {
      _message('请输入已注册的 QQ 邮箱或 751152.xyz 邮箱');
      return;
    }
    setState(() => _sending = true);
    try {
      final info = await _api.requestPasswordResetCode(email);
      if (!mounted) return;
      _codeEmail = email;
      _startResendTimer(info.resendAfterSeconds);
      final minutes = (info.expiresInSeconds / 60).ceil();
      _message('验证码已发送，$minutes 分钟内有效');
    } catch (error) {
      _message(error.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final code = _verificationCode.text.trim();
    final password = _password.text;
    if (!_looksLikePasswordResetEmail(email)) {
      _message('请输入已注册的 QQ 邮箱或 751152.xyz 邮箱');
      return;
    }
    if (_codeEmail != email) {
      _message('请先获取当前邮箱的验证码');
      return;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      _message('请输入 6 位数字验证码');
      return;
    }
    if (password.length < 6 || password.length > 64) {
      _message('新密码长度需要为 6 到 64 位');
      return;
    }
    if (_confirmPassword.text != password) {
      _message('两次输入的新密码不一致');
      return;
    }
    setState(() => _resetting = true);
    try {
      await _api.confirmPasswordReset(email, code, password);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      await context.read<AuthController>().clearSessionAfterPasswordReset();
      if (!mounted) return;
      navigator.popUntil((route) => route.isFirst);
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(content: Text('密码已重置，请使用新密码登录')),
      );
    } catch (error) {
      _message(error.toString());
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  void _startResendTimer(int seconds) {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = seconds < 0 ? 0 : seconds);
    if (_resendSeconds == 0) return;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _resendSeconds <= 1) {
        timer.cancel();
        if (mounted) setState(() => _resendSeconds = 0);
        return;
      }
      setState(() => _resendSeconds--);
    });
  }

  void _onEmailChanged(String value) {
    if (_codeEmail == null || value.trim() == _codeEmail) return;
    _resendTimer?.cancel();
    setState(() {
      _codeEmail = null;
      _resendSeconds = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _AuthPage(
      onBack: () => Navigator.of(context).maybePop(),
      title: '找回密码',
      subtitle: '使用注册邮箱验证码设置新密码',
      children: [
        _AuthField(
          controller: _email,
          hintText: '邮箱',
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
          onChanged: _onEmailChanged,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _AuthField(
                controller: _verificationCode,
                hintText: '6 位验证码',
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.oneTimeCode],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 124,
              height: 56,
              child: OutlinedButton(
                onPressed: _sending || _resendSeconds > 0 ? null : _sendCode,
                child: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _resendSeconds > 0
                            ? '$_resendSeconds 秒后重发'
                            : _codeEmail == null
                                ? '获取验证码'
                                : '重新发送',
                        maxLines: 1,
                      ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _AuthField(
          controller: _password,
          hintText: '新密码',
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newPassword],
          suffix: GIconButton(
            icon: _obscurePassword
                ? Icons.visibility_off_rounded
                : Icons.visibility_rounded,
            tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
            size: 20,
            padding: 9,
            backgroundColor: Colors.transparent,
            onTap: () => setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
        const SizedBox(height: 14),
        _AuthField(
          controller: _confirmPassword,
          hintText: '确认新密码',
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.newPassword],
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 24),
        _AuthPrimaryButton(
          label: '重置密码',
          loading: _resetting,
          onTap: _resetting ? null : _submit,
        ),
      ],
    );
  }

  void _message(String text) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }
}

class _AuthPage extends StatelessWidget {
  const _AuthPage({
    required this.title,
    required this.children,
    this.subtitle,
    this.showBrand = false,
    this.onBack,
  });

  final String title;
  final String? subtitle;
  final bool showBrand;
  final VoidCallback? onBack;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  24,
                  compact ? 28 : 34,
                  24,
                  36,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 424),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showBrand) ...[
                          const _AuthBrand(),
                          SizedBox(height: compact ? 38 : 32),
                        ],
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: compact ? 30 : 32,
                            fontWeight: TypeScale.heavy,
                            height: 1.08,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            subtitle!,
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                        SizedBox(height: compact ? 30 : 34),
                        ...children,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (onBack != null)
            Positioned(
              top: 8,
              left: 6 + macOSWindowControlsInset(context),
              child: GIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                tooltip: '返回',
                size: 18,
                padding: 11,
                onTap: onBack,
              ),
            ),
        ],
      ),
    );
  }
}

class _AuthBrand extends StatelessWidget {
  const _AuthBrand();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.asset(
            'assets/branding/app_icon.png',
            width: 56,
            height: 56,
            semanticLabel: '${AppConfig.appName} 图标',
          ),
        ),
        const SizedBox(width: 14),
        const Text(
          AppConfig.appName,
          style: TextStyle(fontSize: 21, fontWeight: TypeScale.heavy),
        ),
      ],
    );
  }
}

class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.controller,
    required this.hintText,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.obscureText = false,
    this.suffix,
    this.onSubmitted,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final bool obscureText;
  final Widget? suffix;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    );
    return SizedBox(
      height: 56,
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        autofillHints: autofillHints,
        obscureText: obscureText,
        onSubmitted: onSubmitted,
        onChanged: onChanged,
        style: TextStyle(fontSize: 15, color: scheme.onSurface),
        decoration: InputDecoration(
          hintText: hintText,
          filled: true,
          fillColor: dark ? scheme.surfaceContainer : Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          suffixIcon: suffix,
          suffixIconConstraints: suffix == null
              ? null
              : const BoxConstraints.tightFor(width: 48, height: 56),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: BorderSide(color: scheme.primary, width: 1.2),
          ),
        ),
      ),
    );
  }
}

class _AuthPrimaryButton extends StatelessWidget {
  const _AuthPrimaryButton({
    required this.label,
    required this.onTap,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null && !loading;
    return GPressScale(
      onTap: enabled ? onTap : null,
      child: Container(
        height: 56,
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: loading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.onPrimary,
                ),
              )
            : Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: TypeScale.bold,
                  color: enabled ? scheme.onPrimary : scheme.onSurfaceVariant,
                ),
              ),
      ),
    );
  }
}

class _AuthTextButton extends StatelessWidget {
  const _AuthTextButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 38),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: TypeScale.semibold),
      ),
    );
  }
}

class _AuthLink extends StatelessWidget {
  const _AuthLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            color: Theme.of(context).colorScheme.primary,
            decoration: TextDecoration.underline,
            decorationColor: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

bool _looksLikeEmail(String value) {
  final at = value.indexOf('@');
  return at > 0 && value.indexOf('.', at) > at + 1;
}

bool _looksLikePasswordResetEmail(String value) {
  return RegExp(
    r'^(?:[1-9]\d{4,10}@qq\.com|[a-z0-9][a-z0-9._-]{0,63}@751152\.xyz)$',
    caseSensitive: false,
  ).hasMatch(value);
}
