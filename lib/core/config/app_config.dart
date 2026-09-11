/// 全局配置：应用名、后端地址、音乐源、音质参数。
/// 对应 macOS 版 Info.plist 中的 MUSIC_API_BASE_URL。
class AppConfig {
  AppConfig._();

  static const String appName = '柒伍壹壹音乐';

  /// Release builds inject this from pubspec.yaml with --dart-define.
  static const String appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.1.33',
  );

  /// GitHub repository used for release checks and desktop/Android installers.
  static const String updateRepository = String.fromEnvironment(
    'UPDATE_REPOSITORY',
    defaultValue: 'John9816/music',
  );

  /// Keeps Flutter releases separate from the repository's native Android app.
  static const String updateReleaseTagPrefix = String.fromEnvironment(
    'UPDATE_RELEASE_TAG_PREFIX',
    defaultValue: 'flutter-v',
  );

  static const String updateAssetPrefix = String.fromEnvironment(
    'UPDATE_ASSET_PREFIX',
    defaultValue: 'DuckMusic-Flutter-',
  );

  /// Pass with --dart-define=IOS_APP_STORE_ID=123456789 after App Store setup.
  static const String iosAppStoreId = String.fromEnvironment(
    'IOS_APP_STORE_ID',
  );

  /// Optional ECS manifest for the desktop iOS install center.
  static const String iosSideloadManifestUrl = String.fromEnvironment(
    'IOS_SIDELOAD_MANIFEST_URL',
    defaultValue: 'https://api.751152.xyz/ios/latest.json',
  );

  /// Optional absolute path to the local signing helper executable.
  static const String iosSideloadHelperPath = String.fromEnvironment(
    'IOS_SIDELOAD_HELPER_PATH',
  );

  static const String apiBaseUrl = 'https://api.751152.xyz/';
  static const String userContentBaseUrl = 'https://hi.751152.xyz/';

  /// 巡回寺图床：AI 生图结果自动转存后换到的长期外链（落地 ImgBB）。
  static const String imageHostUploadUrl =
      'https://api.xunhuisi.store/API/Tuchuang/Tc.php';

  static const String liveTvM3uUrl =
      // 与本机 Danbo 电视当前使用的直播源保持一致。
      'https://danboxingqiu.cn/iptv.m3u';

  /// source 参数 -> 显示名（与 Android/macOS 版一致）
  static const Map<String, String> musicSources = {
    'netease': '红源',
    'qq': '绿源',
    'kuwo': '橙源',
  };

  /// 音质档位 -> API 参数值（对应 macOS 版 AudioQuality）
  static const Map<String, String> qualityValues = {
    'auto': '320k',
    'standard': '128k',
    'exhigh': '320k',
    'lossless': 'flac',
    'hires': 'flac24bit',
  };

  static const Map<String, String> qualityLabels = {
    'auto': '自动选择',
    'standard': '标准音质',
    'exhigh': '高品质',
    'lossless': '无损音质',
    'hires': 'Hi-Res',
  };
}
