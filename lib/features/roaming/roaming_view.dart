import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/player/roaming_controller.dart';
import '../../widgets/glass.dart';
import '../profile/login_view.dart';
import '../settings/qishui_account_view.dart';
import '../player/player_view.dart';

Future<void> showMusicRoaming(BuildContext context,
    {bool openPlayer = true,
    String? initialMode,
    bool autoStart = false}) async {
  if (!context.read<AuthController>().isLoggedIn) {
    await Navigator.of(context)
        .push(buildAppRoute(context, (_) => const LoginView()));
    if (!context.mounted || !context.read<AuthController>().isLoggedIn) return;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => RoamingView(
          openPlayer: openPlayer,
          initialMode: initialMode,
          autoStart: autoStart));
}

class RoamingView extends StatefulWidget {
  const RoamingView(
      {super.key,
      this.openPlayer = true,
      this.initialMode,
      this.autoStart = false});
  final bool openPlayer, autoStart;
  final String? initialMode;
  @override
  State<RoamingView> createState() => _RoamingViewState();
}

class _RoamingViewState extends State<RoamingView> {
  late final RoamingController _roaming;
  bool _loadingModes = true;
  String? _modeError;
  @override
  void initState() {
    super.initState();
    _roaming = context.read<RoamingController>();
    unawaited(_load());
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_start(widget.initialMode));
      });
    }
  }

  Future<void> _load() async {
    setState(() {
      _loadingModes = true;
      _modeError = null;
    });
    try {
      await _roaming.loadModes();
    } catch (_) {
      if (mounted) _modeError = '场景暂不可用，请检查黑源授权后重试';
    }
    if (mounted) setState(() => _loadingModes = false);
  }

  Future<void> _start(String? mode) async {
    final started = await _roaming.start(modeId: mode);
    if (!mounted || !started) return;
    final root = Navigator.of(context, rootNavigator: true);
    final reduced = MediaQuery.disableAnimationsOf(context);
    root.pop();
    if (root.mounted && widget.openPlayer) {
      root.push(buildPlayerRoute(reducedMotion: reduced));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _roaming,
      builder: (context, _) => SizedBox(
          height: MediaQuery.sizeOf(context).height * .78,
          child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                const Text('音乐漫游',
                    style:
                        TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(_roaming.active
                    ? '正在漫游 · ${_roaming.modeName}'
                    : '跟随你的喜好，听见下一首。'),
                const SizedBox(height: 20),
                ListTile(
                    leading: const Icon(Icons.auto_awesome),
                    title: const Text('为你推荐'),
                    subtitle: const Text('使用已绑定黑源账号的个人推荐'),
                    trailing: const Icon(Icons.play_arrow_rounded),
                    onTap: _roaming.loading ? null : () => _start(null)),
                if (_loadingModes || _roaming.loading)
                  const LinearProgressIndicator(),
                if (_modeError != null || _roaming.error != null)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(children: [
                        Text(_roaming.error ?? _modeError!),
                        Wrap(spacing: 8, children: [
                          TextButton(
                              onPressed: _loadingModes ? null : _load,
                              child: const Text('重新加载')),
                          TextButton(
                              onPressed: () => Navigator.of(context).push(
                                  buildAppRoute(context,
                                      (_) => const QishuiAccountView())),
                              child: const Text('黑源账号')),
                          if (_roaming.active)
                            TextButton(
                                onPressed:
                                    _roaming.loading ? null : _roaming.loadMore,
                                child: const Text('重试续播')),
                        ]),
                      ])),
                for (final group
                    in _roaming.modes.map((m) => m.group).toSet()) ...[
                  Padding(
                      padding: const EdgeInsets.fromLTRB(4, 18, 4, 12),
                      child: Text(group.isEmpty ? '选择场景' : group,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w700))),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final mode
                        in _roaming.modes.where((m) => m.group == group))
                      ChoiceChip(
                          label: Text(mode.name),
                          selected: _roaming.active &&
                              _roaming.session.modeId == mode.id,
                          onSelected:
                              _roaming.loading ? null : (_) => _start(mode.id)),
                  ]),
                ],
                if (_roaming.active)
                  Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: OutlinedButton(
                          onPressed: () {
                            _roaming.stop();
                            Navigator.pop(context);
                          },
                          child: const Text('结束漫游，保留当前播放'))),
              ])));
}

class RoamingSection extends StatefulWidget {
  const RoamingSection({super.key});
  @override
  State<RoamingSection> createState() => _RoamingSectionState();
}

class _RoamingSectionState extends State<RoamingSection> {
  int? _requestedGeneration;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<AuthController?>();
    final controller = context.read<RoamingController?>();
    if (controller == null ||
        auth == null ||
        !auth.isLoggedIn ||
        _requestedGeneration == auth.sessionGeneration) {
      return;
    }
    _requestedGeneration = auth.sessionGeneration;
    unawaited(controller.loadModes().catchError((Object _) {}));
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RoamingController?>();
    if (controller == null) return const SizedBox.shrink();
    return Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(
                child: Text('音乐漫游',
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.w700))),
            TextButton(
                onPressed: () => showMusicRoaming(context),
                child: Text(controller.active ? controller.modeName : '全部场景')),
          ]),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, c) {
            const preferred = ['助眠', '通勤', '健身', 'EMO', '驾车', 'DJ', '抖音'];
            final modes = [
              for (final word in preferred)
                ...controller.modes
                    .where((m) =>
                        m.name.toUpperCase().contains(word.toUpperCase()))
                    .take(1),
            ];
            final used = modes.map((m) => m.id).toSet();
            modes.addAll(controller.modes
                .where((m) => used.add(m.id))
                .take(7 - modes.length));

            final labels = [
              '为你推荐',
              ...modes.map((m) => m.name),
              if (modes.isEmpty) '选择场景'
            ];
            final columns = c.maxWidth < 350 ? 3 : 4;
            return Wrap(spacing: 10, runSpacing: 10, children: [
              for (var i = 0; i < labels.length; i++)
                SizedBox(
                    width: (c.maxWidth - (columns - 1) * 10) / columns,
                    child: GPressScale(
                        onTap: controller.loading
                            ? null
                            : () => showMusicRoaming(context,
                                initialMode: i > 0 && modes.isNotEmpty
                                    ? modes[i - 1].id
                                    : null,
                                autoStart: i == 0 || modes.isNotEmpty),
                        child: Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 18, horizontal: 4),
                            decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: .07),
                                borderRadius: BorderRadius.circular(18)),
                            child: Column(children: [
                              Icon(
                                  [
                                    Icons.auto_awesome,
                                    Icons.nightlight_round,
                                    Icons.headphones,
                                    Icons.fitness_center,
                                    Icons.dark_mode,
                                    Icons.directions_car,
                                    Icons.graphic_eq,
                                    Icons.music_note
                                  ][i % 8],
                                  size: 28),
                              const SizedBox(height: 12),
                              Text(labels[i],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant)),
                            ])))),
            ]);
          }),
        ]));
  }
}
