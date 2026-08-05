import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/notification_api.dart';
import '../../core/auth/auth_controller.dart';
import '../../widgets/glass.dart';

class NotificationsView extends StatefulWidget {
  const NotificationsView({super.key});

  @override
  State<NotificationsView> createState() => _NotificationsViewState();
}

class _NotificationsViewState extends State<NotificationsView> {
  Future<List<AppNotification>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<List<AppNotification>> _load() {
    final token = context.read<AuthController>().token;
    if (token == null) return Future.error('请先登录后查看通知');
    return NotificationApi().getNotifications(token);
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GAppBar(
        title: '通知',
        onBack: () => Navigator.of(context).maybePop(),
        actions: [
          GIconButton(
            icon: Icons.refresh_rounded,
            tooltip: '刷新通知',
            onTap: _reload,
          ),
        ],
      ),
      body: FutureBuilder<List<AppNotification>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(strokeWidth: 2));
          }
          if (snapshot.hasError) {
            return GEmptyState(
              icon: Icons.notifications_off_outlined,
              title: '通知加载失败',
              text: snapshot.error.toString(),
              onRetry: _reload,
            );
          }
          final notifications = snapshot.data ?? const [];
          if (notifications.isEmpty) {
            return const GEmptyState(
              icon: Icons.notifications_none_rounded,
              title: '暂无通知',
              text: '新的服务通知会显示在这里',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            itemCount: notifications.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) =>
                _NotificationCard(notification: notifications[index]),
          );
        },
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final date = notification.createdAt?.toLocal();
    final dateText = date == null
        ? ''
        : '${date.year}.${date.month.toString().padLeft(2, '0')}.'
            '${date.day.toString().padLeft(2, '0')} '
            '${date.hour.toString().padLeft(2, '0')}:'
            '${date.minute.toString().padLeft(2, '0')}';
    return GSurface(
      radius: 8,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            notification.urgent
                ? Icons.warning_amber_rounded
                : Icons.notifications_rounded,
            color: notification.urgent ? scheme.error : scheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notification.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: TypeScale.bold,
                  ),
                ),
                if (notification.content.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    notification.content,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (dateText.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${notification.urgent ? '紧急 · ' : ''}$dateText',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: notification.urgent
                          ? scheme.error
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!notification.read)
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primary,
              ),
            ),
        ],
      ),
    );
  }
}
