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

class AiDrawTaskRecord {
  const AiDrawTaskRecord({
    required this.id,
    required this.prompt,
    required this.status,
    this.size,
    this.count = 1,
    this.model,
    this.errorMessage,
    this.createdAt,
  });

  final int id;
  final String prompt;
  final String status;
  final String? size;
  final int count;
  final String? model;
  final String? errorMessage;
  final String? createdAt;

  bool get isFailed => status == 'FAILED';
  bool get isProcessing => status == 'PENDING' || status == 'PROCESSING';

  factory AiDrawTaskRecord.fromJson(Map<String, dynamic> json) {
    return AiDrawTaskRecord(
      id: AiDrawTask._intValue(json['id']) ?? 0,
      prompt: json['prompt']?.toString() ?? '',
      status: json['status']?.toString().toUpperCase() ?? '',
      size: json['size']?.toString(),
      count: AiDrawTask._intValue(json['n']) ?? 1,
      model: json['model']?.toString(),
      errorMessage: json['errorMessage']?.toString(),
      createdAt: json['createdAt']?.toString(),
    );
  }
}

class AiDrawHistoryItem {
  const AiDrawHistoryItem({
    required this.id,
    required this.prompt,
    required this.imageUrl,
    this.model,
    this.size,
    this.isShared = false,
    this.createdAt,
  });

  final int id;
  final String prompt;
  final String imageUrl;
  final String? model;
  final String? size;
  final bool isShared;
  final String? createdAt;

  AiDrawHistoryItem copyWith({bool? isShared}) => AiDrawHistoryItem(
        id: id,
        prompt: prompt,
        imageUrl: imageUrl,
        model: model,
        size: size,
        isShared: isShared ?? this.isShared,
        createdAt: createdAt,
      );

  factory AiDrawHistoryItem.fromJson(Map<String, dynamic> json) {
    return AiDrawHistoryItem(
      id: AiDrawTask._intValue(json['id']) ?? 0,
      prompt: json['prompt']?.toString() ?? '',
      imageUrl: json['imageUrl']?.toString() ?? '',
      model: json['model']?.toString(),
      size: json['size']?.toString(),
      isShared: json['isShared'] == true,
      createdAt: json['createdAt']?.toString(),
    );
  }
}

class AiDrawPage<T> {
  const AiDrawPage({
    required this.items,
    required this.total,
    required this.page,
    required this.size,
  });

  final List<T> items;
  final int total;
  final int page;
  final int size;

  bool get hasMore => (page + 1) * size < total;
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

  Future<AiDrawPage<AiDrawTaskRecord>> tasks({
    int page = 0,
    int size = 20,
  }) async {
    final data = await _client.getJson(
      'api/user/image/tasks',
      params: {'page': '$page', 'size': '$size'},
    );
    return _page(
      data,
      (json) => AiDrawTaskRecord.fromJson(json),
      fallbackPage: page,
      fallbackSize: size,
    );
  }

  Future<AiDrawTask> task(int taskId) async {
    final data = await _client.getJson('api/user/image/generate/$taskId');
    return AiDrawTask.fromJson(data);
  }

  Future<AiDrawPage<AiDrawHistoryItem>> history({
    int page = 0,
    int size = 20,
  }) async {
    final data = await _client.getJson(
      'api/user/image/history',
      params: {'page': '$page', 'size': '$size'},
    );
    return _page(
      data,
      (json) => AiDrawHistoryItem.fromJson(json),
      fallbackPage: page,
      fallbackSize: size,
    );
  }

  Future<void> setShared(int id, bool shared) async {
    await _client.patchJson(
      'api/user/image/history/$id/share?shared=$shared',
    );
  }

  Future<void> deleteHistory(int id) async {
    await _client.deleteJson('api/user/image/history/$id');
  }

  Future<AiDrawTask> retry(int taskId) async {
    final data = await _client.postJson(
      'api/user/image/history/$taskId/retry',
    );
    return AiDrawTask.fromJson(data);
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
      task = await this.task(taskId);
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

  AiDrawPage<T> _page<T>(
    Map<String, dynamic> data,
    T Function(Map<String, dynamic>) parse, {
    required int fallbackPage,
    required int fallbackSize,
  }) {
    final rawItems = data['items'];
    final items = rawItems is List
        ? rawItems
            .whereType<Map>()
            .map((item) => parse(Map<String, dynamic>.from(item)))
            .toList(growable: false)
        : <T>[];
    return AiDrawPage<T>(
      items: items,
      total: AiDrawTask._intValue(data['total']) ?? items.length,
      page: AiDrawTask._intValue(data['page']) ?? fallbackPage,
      size: AiDrawTask._intValue(data['size']) ?? fallbackSize,
    );
  }
}
