// maeknote — flavor → API base (build-time via --dart-define-from-file=.env.local)
class Env {
  static const appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'local');
  static const flavor = String.fromEnvironment('FLAVOR', defaultValue: 'local');
  static const apiBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:8000');
}
