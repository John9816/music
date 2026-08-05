import 'api_client.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.urgent,
    required this.read,
  });

  final String id;
  final String title;
  final String content;
  final DateTime? createdAt;
  final bool urgent;
  final bool read;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final type = json['type']?.toString().toLowerCase();
    return AppNotification(
      id: (json['id'] ?? json['notificationId'] ?? '').toString(),
      title: (json['title'] ?? json['subject'] ?? '通知').toString(),
      content: (json['content'] ?? json['message'] ?? '').toString(),
      createdAt: DateTime.tryParse(
        (json['createdAt'] ?? json['created_at'] ?? '').toString(),
      ),
      urgent: json['urgent'] == true || type == 'urgent',
      read: json['read'] == true || json['isRead'] == true,
    );
  }
}

class NotificationApi {
  final ApiClient _client = ApiClient.instance;

  Future<List<AppNotification>> getNotifications(String token) async {
    final data = await _client.getJson(
      'api/notifications',
      params: const {'page': '0', 'size': '50'},
      headers: {'Authorization': 'Bearer $token'},
    );
    final raw = data['items'] ?? data['notifications'] ?? data['list'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => AppNotification.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .toList();
  }
}
