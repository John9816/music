/// 第三方歌手资料接口返回的歌手信息。
class ArtistInfo {
  const ArtistInfo({
    required this.name,
    required this.profile,
    this.imageUrl,
  });

  final String name;
  final String? imageUrl;
  final String profile;

  factory ArtistInfo.fromJson(
    Map<String, dynamic> json, {
    String fallbackName = '',
  }) {
    final name = _text(json['name']) ?? fallbackName.trim();
    return ArtistInfo(
      name: name,
      imageUrl: _secureUrl(_text(json['imgurl'])),
      profile: _text(json['profile']) ?? '',
    );
  }
}

String? _text(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

String? _secureUrl(String? value) {
  if (value == null) return null;
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasScheme) return value;
  return uri.scheme == 'http' ? uri.replace(scheme: 'https').toString() : value;
}
