import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/music_social_api.dart';
import '../../core/auth/auth_controller.dart';
import '../../widgets/glass.dart';

/// 听歌时长排行榜：周榜 / 月榜 + 我的听歌数据与排名。
/// 数据来自 website-backend 的 /api/public/music/listening/* 与 /api/user/music/listening/me。
class ListeningRankingView extends StatefulWidget {
  const ListeningRankingView({super.key});

  @override
  State<ListeningRankingView> createState() => _ListeningRankingViewState();
}

class _ListeningRankingViewState extends State<ListeningRankingView> {
  final MusicSocialApi _api = MusicSocialApi();

  int _period = 0; // 0=周榜, 1=月榜
  bool _loading = true;
  String? _error;
  ListenRanking? _ranking;
  MyListenTime? _mine;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final period = _period == 0 ? 'week' : 'month';
    final auth = context.read<AuthController>();
    try {
      final results = await Future.wait([
        _api.getListeningRanking(period: period, limit: 50),
        if (auth.isLoggedIn && auth.token != null)
          _api.getMyListenTime(auth.token!).catchError((_) => const MyListenTime(
                totalSec: 0,
                weekSec: 0,
                monthSec: 0,
                weekRank: 0,
                monthRank: 0,
                weekParticipants: 0,
                monthParticipants: 0,
              )),
      ]);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _ranking = results[0] as ListenRanking;
        _mine = results.length > 1 ? results[1] as MyListenTime : null;
      });
    } catch (error) {
      _showError(error);
    }
  }

  void _switchPeriod(int value) {
    if (value == _period) return;
    setState(() => _period = value);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: GAppBar(
        title: '听歌排行榜',
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _MyListenCard(mine: _mine),
            const SizedBox(height: 18),
            Center(
              child: GSegmented(
                items: const ['本周', '本月'],
                selected: _period,
                onSelected: _switchPeriod,
              ),
            ),
            const SizedBox(height: 16),
            _buildBody(scheme),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ColorScheme scheme) {
    if (_loading && _ranking == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          children: [
            Icon(Icons.wifi_off_rounded, size: 40, color: scheme.outline),
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: scheme.outline)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    final ranking = _ranking;
    if (ranking == null || ranking.items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Center(
          child: Text(
            '暂无听歌记录，快去听歌上榜吧',
            style: TextStyle(color: scheme.outline),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Text(
            '共 ${ranking.participants} 位用户参与 · 按真实播放时长排名',
            style: TextStyle(fontSize: 12, color: scheme.outline),
          ),
        ),
        const SizedBox(height: 8),
        for (final item in ranking.items)
          _RankTile(item: item, highlight: _isMe(item)),
      ],
    );
  }

  bool _isMe(ListenRankItem item) {
    final myId = context.read<AuthController>().userId;
    if (myId == null || item.userId == null) return false;
    return item.userId.toString() == myId;
  }

  void _showError(Object error) {
    if (!mounted) return;
    setState(() => _error = error.toString());
  }
}

class _MyListenCard extends StatelessWidget {
  const _MyListenCard({required this.mine});

  final MyListenTime? mine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final loggedIn = context.watch<AuthController>().isLoggedIn;
    if (!loggedIn || mine == null) {
      return GSurface(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(Icons.person_outline_rounded, color: scheme.outline),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '登录后可查看我的听歌时长与排名',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final weekRank = mine!.weekRank;
    final monthRank = mine!.monthRank;
    return GSurface(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.insights_rounded,
                    size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text('我的听歌数据',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                    child: _stat('累计', _duration(mine!.totalSec))),
                Expanded(child: _stat('本周', _duration(mine!.weekSec))),
                Expanded(child: _stat('本月', _duration(mine!.monthSec))),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _rank('周榜', weekRank, mine!.weekParticipants),
                ),
                Expanded(
                  child: _rank('月榜', monthRank, mine!.monthParticipants),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(value,
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ],
      );

  Widget _rank(String label, int rank, int participants) {
    final rankText = rank > 0 ? '第 $rank 名' : '未上榜';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(rankText,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        Text('$participants 人参与',
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  String _duration(int seconds) {
    if (seconds <= 0) return '0 分钟';
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours > 0) return '$hours 小时 $minutes 分';
    return '$minutes 分钟';
  }
}

class _RankTile extends StatelessWidget {
  const _RankTile({required this.item, required this.highlight});

  final ListenRankItem item;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Color color;
    if (item.rank == 1) {
      color = const Color(0xFFD4AF37);
    } else if (item.rank == 2) {
      color = const Color(0xFFB0BEC5);
    } else if (item.rank == 3) {
      color = const Color(0xFFCD7F32);
    } else {
      color = scheme.primary;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: highlight
            ? scheme.primaryContainer.withValues(alpha: 0.5)
            : scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        leading: SizedBox(
          width: 34,
          child: Text(
            '${item.rank}',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800, color: color),
          ),
        ),
        title: Text(item.username.isEmpty ? '音乐爱好者' : item.username,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('听歌 ${_format(item.seconds)}'),
      ),
    );
  }

  String _format(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    return hours > 0 ? '$hours小时$minutes分' : '$minutes分钟';
  }
}
