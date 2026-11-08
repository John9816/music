import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/player/player_controller.dart';
import '../../core/services/sleep_timer.dart';
import '../../widgets/glass.dart';

Future<void> showReferenceSleepTimer(BuildContext context) async {
  final timer = context.read<SleepTimer>();
  final player = context.read<PlayerController>();
  final value = await showDialog<int>(
      context: context,
      barrierColor: Colors.black26,
      builder: (dialog) => Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                  child: Container(
                    width: 400,
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: .28)),
                        gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0x8ca1a8c4), Color(0x5cd3ce9a)])),
                    child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          const Text('睡眠定时',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 16),
                          if (timer.isActive)
                            _option(dialog, '取消定时 · ${timer.displayText}', -2),
                          for (final minutes in [5, 15, 30, 45, 60])
                            _option(dialog, '$minutes 分钟后暂停', minutes),
                          _option(dialog, '本曲结束后暂停', -1),
                          const Divider(color: Colors.white24, height: 24),
                          _option(dialog, '自定义', 0, arrow: true),
                        ])),
                  ),
                )),
          ));
  if (!context.mounted || value == null) return;
  if (value == -2) {
    timer.stop();
    return;
  }
  if (value == -1) {
    await timer.startAtTrackEnd(configure: player.setStopAtTrackEnd);
    return;
  }
  final minutes = value == 0
      ? await showDialog<int>(
          context: context, builder: (_) => const _CustomSleepTime())
      : value;
  if (minutes != null && context.mounted) {
    timer.start(Duration(minutes: minutes), onTimeout: player.pause);
  }
}

Widget _option(BuildContext context, String label, int result,
        {bool arrow = false}) =>
    GPressScale(
      onTap: () => Navigator.pop(context, result),
      child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(children: [
              Expanded(
                  child: Text(label,
                      style: const TextStyle(
                          color: Color(0xfff3f4f8), fontSize: 16))),
              if (arrow)
                const Icon(Icons.chevron_right_rounded, color: Colors.white70)
            ]),
          )),
    );

class _CustomSleepTime extends StatefulWidget {
  const _CustomSleepTime();
  @override
  State<_CustomSleepTime> createState() => _CustomSleepTimeState();
}

class _CustomSleepTimeState extends State<_CustomSleepTime> {
  final _input = TextEditingController(text: '20');
  String? _error;
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _submit() {
    final minutes = int.tryParse(_input.text.trim());
    if (minutes == null || minutes < 1 || minutes > 1440) {
      setState(() => _error = '请输入 1–1440 分钟');
      return;
    }
    Navigator.pop(context, minutes);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('自定义睡眠时间'),
          content: TextField(
              controller: _input,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: '分钟', errorText: _error),
              onSubmitted: (_) => _submit()),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消')),
            FilledButton(onPressed: _submit, child: const Text('开始计时'))
          ]);
}
