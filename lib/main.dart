import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'api.dart';
import 'app_config.dart';
import 'session.dart';
import 'widgets.dart';
import 'login_screen.dart';
import 'home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MoonApp());
}

class MoonApp extends StatelessWidget {
  const MoonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Moon',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const _Gate(),
    );
  }
}

/// 启动门：恢复会话 → 自动登录 → 进入首页或登录页
class _Gate extends StatefulWidget {
  const _Gate();

  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  bool _ready = false;
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await Api.restore();
    var ok = false;
    if (Api.isLoggedIn) {
      // Cookie 还在，先进首页；请求 401 时再走登录
      ok = true;
      // 后台静默续期 Cookie
      Api.autoLogin();
    } else if (AppConfig.hasBuiltinAccount) {
      // 内置账号静默登录
      ok = await Api.login(
        serverUrl: AppConfig.serverUrl,
        username: AppConfig.username,
        password: AppConfig.password,
      ).then((r) => r.ok);
    } else if (await Session.canAutoLogin) {
      ok = await Api.autoLogin();
    }
    if (!mounted) return;
    setState(() {
      _ready = true;
      _loggedIn = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: kAccent)),
      );
    }
    return _loggedIn ? const HomeScreen() : const LoginScreen();
  }
}
