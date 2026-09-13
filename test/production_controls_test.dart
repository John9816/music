import 'package:duck_music/core/theme/app_theme.dart';
import 'package:duck_music/features/settings/settings_components.dart';
import 'package:duck_music/widgets/glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('page and segmented titles preserve the selected font family',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(fontFamily: 'SelectedFont'),
      home: Scaffold(
        appBar: const GAppBar(title: '设置'),
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GSegmented(
              items: const ['综合', '单曲'],
              selected: 0,
              onSelected: (_) {},
            ),
            const GListTile(title: Text('歌曲名称'), subtitle: Text('歌手名称')),
          ],
        ),
      ),
    ));
    for (final label in ['设置', '综合', '歌曲名称', '歌手名称']) {
      expect(
          DefaultTextStyle.of(tester.element(find.text(label)))
              .style
              .fontFamily,
          'SelectedFont');
    }
  });

  testWidgets('setting labels toggle their switch exactly once',
      (tester) async {
    var enabled = false;
    var changes = 0;
    await tester.pumpWidget(_app(StatefulBuilder(
      builder: (context, setState) {
        void change(bool value) => setState(() {
              enabled = value;
              changes++;
            });
        return SettingsRow(
          icon: Icons.animation,
          title: '减弱动态效果',
          trailing: SettingsSwitch(value: enabled, onChanged: change),
          onToggle: change,
        );
      },
    )));

    await tester.tap(find.text('减弱动态效果'));
    await tester.pumpAndSettle();
    expect(enabled, isTrue);
    expect(changes, 1);
    await tester.tap(find.byType(SettingsSwitch));
    await tester.pumpAndSettle();
    expect(enabled, isFalse);
    expect(changes, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long setting values fit a narrow window with large text',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(_app(
      SettingsRow(
        icon: Icons.keyboard,
        title: '上一首快捷键',
        subtitle: '在任何应用中控制正在播放的音乐',
        value: 'Control + Shift + Arrow Left',
        onTap: () {},
      ),
      scale: 2,
    ));
    expect(find.text('Control + Shift + Arrow Left'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('playback progress exposes adjustable time to assistive input',
      (tester) async {
    final handle = tester.ensureSemantics();
    try {
      var position = const Duration(seconds: 20);
      await tester.pumpWidget(_app(StatefulBuilder(
        builder: (context, setState) => GProgressBar(
          position: position,
          duration: const Duration(seconds: 100),
          onSeek: (value) => setState(() => position = value),
        ),
      )));

      final progress = find.bySemanticsLabel('播放进度');
      expect(progress, findsOneWidget);
      var node = tester.getSemantics(progress);
      expect(node.getSemanticsData().value, contains('0:20'));
      expect(
          node.getSemanticsData().hasAction(SemanticsAction.increase), isTrue);
      node.owner!.performAction(node.id, SemanticsAction.increase);
      await tester.pump();
      expect(position, const Duration(seconds: 25));
      node = tester.getSemantics(progress);
      node.owner!.performAction(node.id, SemanticsAction.decrease);
      await tester.pump();
      expect(position, const Duration(seconds: 20));

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(position, const Duration(seconds: 25));
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      expect(position, const Duration(seconds: 100));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(position, const Duration(seconds: 100));
      expect(tester.takeException(), isNull);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('unknown playback duration is not an adjustable control',
      (tester) async {
    final handle = tester.ensureSemantics();
    try {
      var changes = 0;
      await tester.pumpWidget(_app(GProgressBar(
        position: Duration.zero,
        duration: Duration.zero,
        onSeek: (_) => changes++,
      )));
      final node = tester.getSemantics(find.byType(GProgressBar));
      expect(
          node.getSemanticsData().hasAction(SemanticsAction.increase), isFalse);
      await tester.tap(find.byType(GProgressBar));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(changes, 0);
    } finally {
      handle.dispose();
    }
  });
}

Widget _app(Widget child, {double scale = 1}) => MaterialApp(
      theme: AppTheme.forAccent('forestGreen', dark: false)
          .data
          .copyWith(platform: TargetPlatform.windows),
      home: Builder(builder: (context) {
        return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: child,
              ),
            ),
          ),
        );
      }),
    );
