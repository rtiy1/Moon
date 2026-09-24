import 'package:flutter/material.dart';

import 'api.dart';
import 'models.dart';
import 'session.dart';
import 'widgets.dart';
import 'home_screen.dart';

/// 登录页：服务器地址 + 用户名/密码（localstorage 模式仅需密码）。
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _serverCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  ServerConfig? _serverConfig;
  bool _probing = false;
  bool _logging = false;
  String? _probeError;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  Future<void> _prefill() async {
    final url = await Session.serverUrl;
    final user = await Session.username;
    if (url != null) _serverCtrl.text = url;
    if (user != null) _userCtrl.text = user;
    if (url != null) _probe();
  }

  @override
  void dispose() {
    _serverCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  /// 探测服务器（获取存储类型和站点名）
  Future<void> _probe() async {
    final url = _serverCtrl.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _probing = true;
      _probeError = null;
      _serverConfig = null;
    });
    final r = await Api.probeServer(url);
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
    final url = _serverCtrl.text.trim();
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text;
    if (url.isEmpty || pass.isEmpty) {
      toast(context, '请填写服务器地址和密码', error: true);
      return;
    }
    // DB 模式需要用户名；localstorage 模式用户名留空也可以（后端忽略）
    final needUser = _serverConfig?.hasUserAccounts ?? true;
    if (needUser && user.isEmpty) {
      toast(context, '请填写用户名', error: true);
      return;
    }
    setState(() => _logging = true);
    final r = await Api.login(
      serverUrl: url,
      username: user.isEmpty ? 'user' : user,
      password: pass,
    );
    if (!mounted) return;
    setState(() => _logging = false);
    if (r.ok) {
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
    final needUser = _serverConfig?.hasUserAccounts ?? true;

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
                      ? 'LunaTV v${_serverConfig!.version} · ${_serverConfig!.storageType}'
                      : '连接到你的 LunaTV 服务器',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                ),
                const SizedBox(height: 36),
                TextField(
                  controller: _serverCtrl,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: '服务器地址',
                    hintText: 'https://tv.example.com',
                    prefixIcon: const Icon(Icons.dns_outlined),
                    border: const OutlineInputBorder(),
                    suffixIcon: _probing
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : IconButton(
                            icon: const Icon(Icons.wifi_find),
                            onPressed: _probe,
                          ),
                  ),
                  onSubmitted: (_) => _probe(),
                ),
                if (_probeError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_probeError!,
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 12)),
                  ),
                const SizedBox(height: 16),
                if (needUser)
                  TextField(
                    controller: _userCtrl,
                    decoration: const InputDecoration(
                      labelText: '用户名',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                  ),
                if (needUser) const SizedBox(height: 16),
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
