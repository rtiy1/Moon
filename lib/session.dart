import 'package:shared_preferences/shared_preferences.dart';

/// 会话存储：服务器地址、账号、Cookie 持久化（SharedPreferences）。
class Session {
  static const _kServerUrl = 'server_url';
  static const _kUsername = 'username';
  static const _kPassword = 'password';
  static const _kCookie = 'auth_cookie';
  static const _kSiteName = 'site_name';

  static Future<void> save({
    required String serverUrl,
    required String username,
    required String password,
    required String cookie,
    String? siteName,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kServerUrl, _normalize(serverUrl));
    await p.setString(_kUsername, username);
    await p.setString(_kPassword, password);
    await p.setString(_kCookie, cookie);
    if (siteName != null) await p.setString(_kSiteName, siteName);
  }

  static String _normalize(String url) {
    var u = url.trim();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'https://$u';
    }
    return u;
  }

  static Future<String?> get serverUrl async =>
      (await SharedPreferences.getInstance()).getString(_kServerUrl);

  static Future<String?> get username async =>
      (await SharedPreferences.getInstance()).getString(_kUsername);

  static Future<String?> get password async =>
      (await SharedPreferences.getInstance()).getString(_kPassword);

  static Future<String?> get cookie async =>
      (await SharedPreferences.getInstance()).getString(_kCookie);

  static Future<String?> get siteName async =>
      (await SharedPreferences.getInstance()).getString(_kSiteName);

  /// 是否具备自动登录条件
  static Future<bool> get canAutoLogin async {
    final u = await serverUrl;
    final p = await password;
    return u != null && u.isNotEmpty && p != null && p.isNotEmpty;
  }

  /// 退出登录：保留服务器地址和用户名，清除密码与 Cookie
  static Future<void> logout() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kPassword);
    await p.remove(_kCookie);
  }

  static Future<void> clearAll() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kServerUrl);
    await p.remove(_kUsername);
    await p.remove(_kPassword);
    await p.remove(_kCookie);
  }

  /// 更新本地保存的密码（改密成功后保持自动登录可用）
  static Future<void> updatePassword(String newPassword) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPassword, newPassword);
  }
}
