import 'package:flutter/material.dart';

import 'api.dart';
import 'app_config.dart';
import 'models.dart';
import 'session.dart';
import 'widgets.dart';
import 'home_screen.dart';

/// 登录页：服务器固定为 AppConfig.serverUrl；
/// - 配置了内置账号时启动即自动登录（Gate 已做，进此页说明失败或未配置）
/// - 手动登录只填用户名 + 密码（localstorage 模式只填密码）
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  ServerConfig? _serverConfig;
  bool _probing = true;
  bool _logging = false;
  String? _probeError;

  bool get _needUser => _serverConfig?.hasUserAccounts ?? true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final user = await Session.username;
    if (user != null) _userCtrl.text = user;
    await _probe();
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _probe() async {
    setState(() {
      _probing = true;
      _probeError = null;
    });
    final r = await Api.probeServer(AppConfig.serverUrl);
    if (!mounted) return;
    setState(() {
      _probing = false;
      if (r.ok) {
        _serverConfig = r.data;
      } else {
        _probeError = r.error;
      }
    });
  }

  Future<void> _login() async {
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text;
    if (pass.isEmpty) {
      toast(context, '请填写密码', error: true);
      return;
    }
    if (_needUser && user.isEmpty) {
      toast(context, '请填写用户名', error: true);
      return;
    }
    setState(() => _logging = true);
    final r = await Api.login(
      serverUrl: AppConfig.serverUrl,
      username: user.isEmpty ? 'user' : user,
      password: pass,
    );
    if (!mounted) return;
    setState(() => _logging = false);
    if (r.ok) {
      // 手动登录成功 → 后续启动用这个账号，不再回落内置账号
      await Session.markUserOverride();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    } else {
      toast(context, r.error ?? '登录失败', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                Icon(Icons.nightlight_round,
                    size: 64, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 12),
                Text(
                  _serverConfig?.siteName ?? 'Moon',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  _serverConfig != null
                      ? '${_serverConfig!.version} · ${AppConfig.serverUrl}'
                      : AppConfig.serverUrl,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                ),
                if (_probing)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Center(
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))),
                  )
                else if (_probeError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Column(
                      children: [
                        Text(_probeError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.redAccent, fontSize: 12)),
                        TextButton(
                            onPressed: _probe, child: const Text('重试')),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                if (_needUser)
                  TextField(
                    controller: _userCtrl,
                    decoration: const InputDecoration(
                      labelText: '用户名',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                  ),
                if (_needUser) const SizedBox(height: 16),
                TextField(
                  controller: _passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '密码',
                    prefixIcon: Icon(Icons.lock_outline),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _login(),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _logging ? null : _login,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: kAccent,
                  ),
                  child: _logging
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('登 录', style: TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 40),
                Text(
                  'Moon App · LunaTV 移动端',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[600] : Colors.grey[400]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
