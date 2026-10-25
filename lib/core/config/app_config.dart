/// Build-time configuration, supplied with `--dart-define` so credentials are
/// never committed:
///
/// ```sh
/// flutter run --dart-define=TG_API_ID=12345 --dart-define=TG_API_HASH=abc...
/// ```
///
/// Obtain both at https://my.telegram.org.
abstract final class AppConfig {
  static const apiId = int.fromEnvironment('TG_API_ID');
  static const apiHash = String.fromEnvironment('TG_API_HASH');

  /// Use Telegram's test data centers (separate accounts, no real users).
  static const useTestDc = bool.fromEnvironment('TG_TEST_DC');

  static const applicationVersion = '0.1.0';
}

/// TDLib init parameters that come from the build, not the device.
/// Injected so tests can run without `--dart-define`.
class TdSettings {
  const TdSettings({
    required this.apiId,
    required this.apiHash,
    this.useTestDc = false,
    this.applicationVersion = AppConfig.applicationVersion,
  });

  const TdSettings.fromEnvironment()
    : apiId = AppConfig.apiId,
      apiHash = AppConfig.apiHash,
      useTestDc = AppConfig.useTestDc,
      applicationVersion = AppConfig.applicationVersion;

  final int apiId;
  final String apiHash;
  final bool useTestDc;
  final String applicationVersion;

  bool get hasApiCredentials => apiId != 0 && apiHash.isNotEmpty;
}
