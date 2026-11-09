import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/player/equalizer_controller.dart';
import '../../core/player/player_controller.dart';
import '../../widgets/glass.dart';

Future<void> showEqualizer(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const EqualizerView(),
    );

class EqualizerView extends StatefulWidget {
  const EqualizerView({super.key});
  @override
  State<EqualizerView> createState() => _EqualizerViewState();
}

class _EqualizerViewState extends State<EqualizerView> {
  late final EqualizerController _eq;
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    _eq = context.read<PlayerController>().equalizer;
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() => _loading = true);
    await _eq.initialize();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _eq,
        builder: (context, _) => SizedBox(
          height: MediaQuery.sizeOf(context).height * .78,
          child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
              children: [
                Row(children: [
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        const Text('均衡器',
                            style: TextStyle(
                                fontSize: 28, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Text(
                            '${EqualizerController.presets[_eq.preset] ?? '自定义'} · ${_eq.enabled ? '已开启' : '已旁路，保留参数'}'),
                      ])),
                  Switch.adaptive(
                      value: _eq.enabled,
                      onChanged: _eq.available ? _eq.setEnabled : null),
                ]),
                const SizedBox(height: 24),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (!_eq.available)
                  GEmptyState(
                      icon: Icons.equalizer_rounded,
                      text: _eq.supported
                          ? (_eq.error ?? '请先播放一首歌曲以启用音效')
                          : '当前平台暂不支持应用内均衡器',
                      onRetry: _eq.supported ? _initialize : null)
                else ...[
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                        color:
                            Theme.of(context).colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(22)),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('输出保护',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Text('增益余量  −${_eq.headroom.toStringAsFixed(1)} dB',
                              style: const TextStyle(
                                  fontSize: 25, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          const Text('各频段统一预留增益余量，减少削波风险。可调频段由设备决定。'),
                        ]),
                  ),
                  const SizedBox(height: 24),
                  Row(children: [
                    const Expanded(
                        child: Text('预设',
                            style: TextStyle(
                                fontSize: 22, fontWeight: FontWeight.w700))),
                    TextButton(
                        onPressed: () => _eq.selectPreset('flat'),
                        child: const Text('重置')),
                  ]),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    for (final p in EqualizerController.presets.entries)
                      ChoiceChip(
                          label: Text(p.value),
                          selected: _eq.preset == p.key,
                          onSelected: (_) => _eq.selectPreset(p.key)),
                  ]),
                  const SizedBox(height: 24),
                  const Text('频段',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text('双击频率可归零',
                      style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 16),
                  SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        for (var i = 0; i < _eq.frequencies.length; i++)
                          SizedBox(
                              width: 62,
                              child: Column(children: [
                                Text(
                                    '${_eq.gains[i] > 0 ? '+' : ''}${_eq.gains[i].toStringAsFixed(1)}',
                                    style: const TextStyle(fontFeatures: [
                                      FontFeature.tabularFigures()
                                    ])),
                                SizedBox(
                                    height: 220,
                                    child: RotatedBox(
                                        quarterTurns: 3,
                                        child: Slider(
                                            value: _eq.gains[i],
                                            min: _eq.minDb,
                                            max: _eq.maxDb,
                                            divisions:
                                                ((_eq.maxDb - _eq.minDb) * 2)
                                                    .round()
                                                    .clamp(1, 120),
                                            semanticFormatterCallback: (v) =>
                                                '${_frequency(_eq.frequencies[i])}赫兹 ${v.toStringAsFixed(1)}分贝',
                                            onChanged: (value) =>
                                                _eq.setGain(i, value)))),
                                GestureDetector(
                                    onDoubleTap: () => _eq.setGain(i, 0),
                                    child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Text(
                                            _frequency(_eq.frequencies[i])))),
                              ])),
                      ])),
                  if (_eq.error != null)
                    Text(_eq.error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                ],
              ]),
        ),
      );
  String _frequency(double hz) => hz < 1000
      ? hz.round().toString()
      : '${(hz / 1000).toStringAsFixed(hz % 1000 == 0 ? 0 : 1)}K';
}
