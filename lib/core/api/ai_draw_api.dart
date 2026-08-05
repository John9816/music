import 'dart:convert';
import 'package:http/http.dart' as http;

class AiDrawApi {
  static const _url = 'https://ecyapi.cn/API/ai_draw_juhe.php';

  Future<String?> generate(String prompt, {String? referenceImage}) async {
    final body = <String, String>{
      'msg': prompt,
      if (referenceImage != null) 'img': referenceImage,
    };
    final res = await http.post(
      Uri.parse(_url),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: body.map((k, v) => MapEntry(k, Uri.encodeComponent(v))),
    );
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return json['image_url'] as String?;
  }
}
