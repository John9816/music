import 'app_config.dart';

class AudioQualityOption {
  const AudioQualityOption({
    required this.id,
    required this.label,
    required this.detail,
    this.isDefault = false,
  });

  final String id;
  final String label;
  final String detail;
  final bool isDefault;
}

const _defaultQualityOptions = [
  AudioQualityOption(
    id: 'auto',
    label: '智能选择',
    detail: '根据网络状况自动选择',
    isDefault: true,
  ),
  AudioQualityOption(id: 'standard', label: '标准音质', detail: '128 Kbps'),
  AudioQualityOption(id: 'exhigh', label: '高清臻音', detail: '320 Kbps'),
  AudioQualityOption(id: 'lossless', label: '无损 SQ', detail: 'FLAC'),
  AudioQualityOption(id: 'hires', label: 'Hi-Res', detail: 'FLAC 24-bit'),
];

const _qqQualityOptions = [
  AudioQualityOption(id: 'standard', label: '标准音质', detail: '128 Kbps'),
  AudioQualityOption(
    id: 'exhigh',
    label: '高品质',
    detail: '320 Kbps',
    isDefault: true,
  ),
  AudioQualityOption(id: 'lossless', label: '无损音质', detail: 'FLAC'),
];

const _qishuiQualityOptions = [
  AudioQualityOption(id: 'standard', label: '标准音质', detail: '128 Kbps'),
  AudioQualityOption(
      id: 'exhigh', label: '高品质', detail: '320 Kbps', isDefault: true),
  AudioQualityOption(id: 'lossless', label: '无损音质', detail: 'FLAC'),
  AudioQualityOption(id: 'hires', label: 'Hi-Res', detail: 'FLAC 24-bit'),
];

List<AudioQualityOption> qualityOptionsForSource(String source) =>
    AppConfig.isQishui(source)
        ? _qishuiQualityOptions
        : _normalizeSource(source) == 'qq'
            ? _qqQualityOptions
            : _defaultQualityOptions;

String defaultQualityForSource(String source) =>
    qualityOptionsForSource(source).firstWhere((option) => option.isDefault).id;

String normalizeQualityForSource(String source, String quality) {
  final normalized = quality.trim().toLowerCase() == 'high'
      ? 'exhigh'
      : quality.trim().toLowerCase();
  final supported = qualityOptionsForSource(source);
  if (supported.any((option) => option.id == normalized)) return normalized;
  return defaultQualityForSource(source);
}

String qualityLabelForSource(String source, String quality) {
  final normalized = normalizeQualityForSource(source, quality);
  return qualityOptionsForSource(source)
      .firstWhere((option) => option.id == normalized)
      .label;
}

String qualitySupportSummary(String source) => AppConfig.isQishui(source)
    ? '支持 128K、320K、FLAC 与 Hi-Res，实际以解析结果为准'
    : _normalizeSource(source) == 'qq'
        ? '支持 128K、320K 与 FLAC'
        : '支持智能选择与多档音质';

String sourceDisplayName(String source) =>
    AppConfig.musicSources[_normalizeSource(source)] ?? source;

String _normalizeSource(String source) =>
    AppConfig.normalizeMusicSource(source);
