class BookUserSource {
  const BookUserSource({
    required this.id,
    required this.sourceId,
    required this.name,
    required this.url,
    required this.type,
    required this.enabled,
    required this.status,
    required this.message,
  });

  final int id;
  final String sourceId;
  final String name;
  final String url;
  final String type;
  final bool enabled;
  final String status;
  final String message;

  bool get ready => status == 'ready';

  factory BookUserSource.fromJson(Map<String, dynamic> json) => BookUserSource(
        id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
        sourceId: json['sourceId']?.toString() ?? '',
        name: json['sourceName']?.toString() ?? '未命名书源',
        url: json['sourceUrl']?.toString() ?? '',
        type: json['sourceType']?.toString() ?? 'book',
        enabled: json['enabled'] == true,
        status: json['status']?.toString() ?? 'unsupported',
        message: json['message']?.toString() ?? '',
      );
}
