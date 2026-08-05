import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_controller.dart';
import '../../widgets/glass.dart';

/// 登录 / 注册页
class LoginView extends StatefulWidget {
  const LoginView({super.key, this.allowBack = true});

  final bool allowBack;

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _registerMode = false;

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = context.read<AuthController>();
    final username = _username.text.trim();
    final password = _password.text;
    if (username.isEmpty || password.isEmpty) return;
    final ok = _registerMode
        ? await auth.register(username, _email.text.trim(), password)
        : await auth.login(username, password);
    if (!mounted) return;
    if (ok) {
      if (widget.allowBack) Navigator.of(context).maybePop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.error ?? '操作失败')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    return Scaffold(
      appBar: GAppBar(
        title: _registerMode ? '注册' : '登录',
        onBack:
            widget.allowBack ? () => Navigator.of(context).maybePop() : null,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(28),
            children: [
              TextField(
                controller: _username,
                decoration: const InputDecoration(labelText: '用户名'),
              ),
              const SizedBox(height: 14),
              if (_registerMode) ...[
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: '邮箱'),
                ),
                const SizedBox(height: 14),
              ],
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: '密码'),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 24),
              GButton(
                label: _registerMode ? '注册并登录' : '登录',
                expand: true,
                loading: auth.loading,
                onTap: auth.loading ? null : _submit,
              ),
              const SizedBox(height: 10),
              Center(
                child: GestureDetector(
                  onTap: () => setState(() => _registerMode = !_registerMode),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      _registerMode ? '已有账号？去登录' : '没有账号？去注册',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
