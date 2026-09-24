/// 编译期配置：通过 --dart-define 注入，避免把凭据写进仓库。
///
/// 本地运行示例：
///   flutter run --dart-define=MOON_USERNAME=admin --dart-define=MOON_PASSWORD=xxx
/// CI 构建时由 GitHub Secrets/Variables 注入。
class AppConfig {
  /// 默认服务器地址（env 为空串时兜底到内置地址）
  static const _serverEnv = String.fromEnvironment(
    'MOON_SERVER',
    defaultValue: 'https://tv.mrchevy.cn',
  );
  static String get serverUrl =>
      _serverEnv.isEmpty ? 'https://tv.mrchevy.cn' : _serverEnv;

  /// 内置账号（可选）。留空则启动时进入登录页。
  static const username = String.fromEnvironment('MOON_USERNAME');
  static const password = String.fromEnvironment('MOON_PASSWORD');

  static bool get hasBuiltinAccount =>
      username.isNotEmpty && password.isNotEmpty;
}
