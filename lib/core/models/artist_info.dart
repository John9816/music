/// 歌手资料接口返回的歌手信息。
class ArtistInfo {
  const ArtistInfo({
    required this.name,
    required this.profile,
    this.imageUrl,
    this.songCount,
    this.albumCount,
  });

  final String name;
  final String? imageUrl;
  final String profile;
  final int? songCount;
  final int? albumCount;

  factory ArtistInfo.fromJson(
    Map<String, dynamic> json, {
    String fallbackName = '',
  }) {
    final name = _text(json['name']) ?? fallbackName.trim();
    return ArtistInfo(
      name: name,
      imageUrl: _secureUrl(
        _text(
          json['imgurl'] ??
              json['imageUrl'] ??
              json['picUrl'] ??
              json['avatar'] ??
              json['coverUrl'],
        ),
      ),
      profile: _text(json['profile'] ?? json['description']) ?? '',
      songCount: _int(json['songCount']),
      albumCount: _int(json['albumCount']),
    );
  }
}

int? _int(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
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
