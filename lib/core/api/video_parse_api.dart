import 'dart:convert';
import 'package:http/http.dart' as http;

class VideoParseApi {
  static const _urls = [
    'https://api.qhsou.com/api/ygdf.php',
    'https://www.yx520.ltd/API/jhjx/api.php',
  ];

  Future<String?> parse(String url) async {
    for (final base in _urls) {
      try {
        final uri = Uri.parse(base).replace(queryParameters: {
          'url': Uri.encodeComponent(url),
          'type': 'json',
        });
        final res = await http.get(uri, headers: {
          'User-Agent': 'Mozilla/5.0',
        });
        final json = jsonDecode(utf8.decode(res.bodyBytes));
        final result = json is Map
            ? (json['url'] as String? ?? json['data'] as String?)
            : null;
        if (result != null) return result;
      } catch (_) {}
    }
    return null;
  }
}
