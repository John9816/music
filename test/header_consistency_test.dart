import 'package:duck_music/core/theme/app_theme.dart';
import 'package:duck_music/widgets/glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('root and detail headers share the first row and side inset',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Future<void> show(Widget header) => tester.pumpWidget(MaterialApp(
          theme: AppTheme.byId('light')
              .data
              .copyWith(platform: TargetPlatform.android),
          home: Scaffold(body: SafeArea(child: header)),
        ));
    await show(GAppBar(title: '设置', onBack: () {}));
    final back = tester.getRect(find.byTooltip('返回'));
    final detailCenter = tester.getCenter(find.text('设置')).dy;
    expect(back.left, 20);
    expect(back.size, const Size(48, 48));
    await show(const GPageHeader(title: '我的'));
    expect(tester.getTopLeft(find.text('我的')).dx, back.left);
    expect(tester.getCenter(find.text('我的')).dy, closeTo(detailCenter, .1));
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 390.0]) {
    testWidgets(
        'long header keeps every action usable at $width and large text',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
              size: Size(width, 844),
              textScaler: const TextScaler.linear(2),
              padding: const EdgeInsets.only(top: 47)),
          child: Scaffold(
              appBar: GAppBar(
            title: '很长的歌单标题也不应该遮挡按钮',
            onBack: () => taps++,
            actions: [
              for (final label in ['搜索', '刷新', '更多'])
                GToolbarButton(
                    icon: Icons.more_horiz,
                    tooltip: label,
                    onTap: () => taps++),
            ],
          )),
        ),
      ));
      final title = tester.getRect(find.text('很长的歌单标题也不应该遮挡按钮'));
      final search = tester.getRect(find.byTooltip('搜索'));
      final back = tester.getRect(find.byTooltip('返回'));
      expect(title.left, greaterThanOrEqualTo(back.right));
      expect(title.right, lessThanOrEqualTo(search.left));
      expect(back.top, 55);
      for (final label in ['返回', '搜索', '刷新', '更多']) {
        final target = find.byTooltip(label);
        expect(tester.getSize(target), const Size(48, 48));
        await tester
            .tapAt(tester.getRect(target).bottomRight - const Offset(1, 1));
        await tester.pump();
      }
      expect(taps, 4);
      expect(tester.takeException(), isNull);
    });
  }
}
