import 'api_client.dart';

class AiDrawModel {
  const AiDrawModel({
    required this.id,
    this.object,
    this.ownedBy,
  });

  final String id;
  final String? object;
  final String? ownedBy;

  factory AiDrawModel.fromJson(Map<String, dynamic> json) {
    return AiDrawModel(
      id: json['id']?.toString() ?? '',
      object: json['object']?.toString(),
      ownedBy: json['ownedBy']?.toString() ?? json['owned_by']?.toString(),
    );
  }
}

class AiDrawImage {
  const AiDrawImage({this.url, this.b64Json});

  final String? url;
  final String? b64Json;

  String? get source {
    final imageUrl = url?.trim();
    if (imageUrl != null && imageUrl.isNotEmpty) return imageUrl;

    final base64 = b64Json?.trim();
    if (base64 != null && base64.isNotEmpty) {
      return 'data:image/png;base64,$base64';
    }
    return null;
  }

  factory AiDrawImage.fromJson(Map<String, dynamic> json) {
    return AiDrawImage(
      url: json['url']?.toString(),
      b64Json: json['b64Json']?.toString() ?? json['b64_json']?.toString(),
    );
  }
}

class AiDrawTask {
  const AiDrawTask({
    required this.id,
    required this.status,
    this.errorMessage,
    this.images = const [],
  });

  final int? id;
  final String status;
  final String? errorMessage;
  final List<AiDrawImage> images;

  String? get imageSource {
    for (final image in images) {
      final source = image.source;
      if (source != null) return source;
    }
    return null;
  }

  factory AiDrawTask.fromJson(Map<String, dynamic> json) {
    final result = json['result'];
    final resultMap = result is Map
        ? Map<String, dynamic>.from(result)
        : const <String, dynamic>{};
    final rawImages = resultMap['data'];

    return AiDrawTask(
      id: _intValue(json['id']),
      status: json['status']?.toString().toUpperCase() ?? '',
      errorMessage: json['errorMessage']?.toString(),
      images: rawImages is List
          ? rawImages
              .whereType<Map>()
              .map((item) =>
                  AiDrawImage.fromJson(Map<String, dynamic>.from(item)))
              .toList(growable: false)
          : const [],
    );
  }

  static int? _intValue(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

/// Client for the backend's authenticated asynchronous image APIs.
class AiDrawApi {
  AiDrawApi({
    ApiClient? client,
    this.pollInterval = const Duration(seconds: 1),
    this.pollTimeout = const Duration(minutes: 2),
  }) : _client = client ?? ApiClient.instance;

  final ApiClient _client;
  final Duration pollInterval;
  final Duration pollTimeout;

  Future<List<AiDrawModel>> models() async {
    final data = await _client.getJson('api/user/image/models');
    final raw = data['list'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => AiDrawModel.fromJson(Map<String, dynamic>.from(item)))
        .where((model) => model.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<String> generate(
    String prompt, {
    String? model,
    String? size,
    int? n,
  }) async {
    final value = _validatePrompt(prompt);
    final task = await _submit(
      prompt: value,
      model: model,
      size: size,
      n: n,
    );
    return _waitForImage(task);
  }

  Future<String> edit({
    required List<int> bytes,
    required String filename,
    required String prompt,
    String? model,
    String? size,
    int? n,
  }) async {
    if (bytes.isEmpty) throw ApiException('请选择要编辑的图片');
    final value = _validatePrompt(prompt);
    final data = await _client.postMultipart(
      'api/user/image/edit',
      fieldName: 'image',
      bytes: bytes,
      filename: filename,
      contentType: _contentType(filename),
      fields: {
        'prompt': value,
        if (model != null && model.trim().isNotEmpty) 'model': model.trim(),
        if (size != null && size.trim().isNotEmpty) 'size': size.trim(),
        if (n != null) 'n': '$n',
      },
    );
    return _waitForImage(AiDrawTask.fromJson(data));
  }

  String _validatePrompt(String prompt) {
    final value = prompt.trim();
    if (value.isEmpty) throw ApiException('请输入图片描述');
    return value;
  }

  Future<AiDrawTask> _submit({
    required String prompt,
    String? model,
    String? size,
    int? n,
  }) async {
    final data = await _client.postJson('api/user/image/generate', body: {
      'prompt': prompt,
      if (model != null && model.trim().isNotEmpty) 'model': model.trim(),
      if (size != null && size.trim().isNotEmpty) 'size': size.trim(),
      if (n != null) 'n': n,
    });
    return AiDrawTask.fromJson(data);
  }

  Future<String> _waitForImage(AiDrawTask initialTask) async {
    var task = initialTask;
    final taskId = task.id;
    if (taskId == null) throw ApiException('服务响应缺少任务 ID');

    final deadline = DateTime.now().add(pollTimeout);
    while (true) {
      final status = task.status;
      if (status == 'COMPLETED') {
        final source = task.imageSource;
        if (source == null) throw ApiException('生成完成但未返回图片');
        return source;
      }
      if (status == 'FAILED' || status == 'CANCELLED') {
        throw ApiException(task.errorMessage?.trim().isNotEmpty == true
            ? task.errorMessage!.trim()
            : '图片生成失败');
      }
      if (DateTime.now().isAfter(deadline)) {
        throw ApiException('图片生成超时，请稍后查看任务状态');
      }

      await Future<void>.delayed(pollInterval);
      final data = await _client.getJson('api/user/image/generate/$taskId');
      task = AiDrawTask.fromJson(data);
    }
  }

  String? _contentType(String filename) {
    switch (filename.split('.').last.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return null;
    }
  }
}
