const _browserUserAgent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
    'AppleWebKit/537.36';

String? normalizeRemoteImageUrl(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;

  final absolute = trimmed.startsWith('//') ? 'https:$trimmed' : trimmed;
  final uri = Uri.tryParse(absolute);
  if (uri == null) return absolute;
  if (uri.scheme == 'http' && _isNetEaseImageHost(uri.host)) {
    return uri.replace(scheme: 'https').toString();
  }
  return absolute;
}

Map<String, String> imageRequestHeaders(String? imageUrl) {
  final uri = imageUrl == null ? null : Uri.tryParse(imageUrl);
  if (uri == null || !_isNetEaseImageHost(uri.host)) return const {};
  return const {
    'User-Agent': _browserUserAgent,
    'Referer': 'https://music.163.com/',
  };
}

bool _isNetEaseImageHost(String host) {
  final normalized = host.trim().toLowerCase();
  return normalized == 'music.126.net' || normalized.endsWith('.music.126.net');
}
