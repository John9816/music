import 'package:duck_music/widgets/glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 顶部安全区有两个入口：外层 SafeArea（二级页）和页头组件自身（主页面）。
/// 两者必须互斥，否则会双重避让，页面整体下沉一截。
void main() {
  testWidgets('页头自己让开顶部 inset，已包在 SafeArea 里不重复让', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<double> titleTop({required double inset, required bool safe}) async {
      const header = GPageHeader(title: '探索');
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(390, 844),
            padding: EdgeInsets.only(top: inset),
          ),
          child: Scaffold(body: safe ? const SafeArea(child: header) : header),
        ),
      ));
      return tester.getTopLeft(find.text('探索')).dy;
    }

    final bare = await titleTop(inset: 0, safe: false);
    final pageOwned = await titleTop(inset: 44, safe: false);
    final safeAreaOwned = await titleTop(inset: 44, safe: true);

    // 页面自己铺到顶部时，页头让出整段 inset。
    expect(pageOwned - bare, closeTo(44, .1));
    // SafeArea 已经把 inset 吃掉，页头再让就会变成 88 的双重避让。
    expect(safeAreaOwned, closeTo(pageOwned, .1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('GToolbar 只有显式声明才让顶部 inset', (tester) async {
    Future<double> toolbarHeight({required bool includeTopInset}) async {
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            padding: EdgeInsets.only(top: 44),
          ),
          child: Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GToolbar(
                  title: const Text('资料库'),
                  includeTopInset: includeTopInset,
                ),
              ],
            ),
          ),
        ),
      ));
      return tester.getSize(find.byType(GToolbar)).height;
    }

    expect(await toolbarHeight(includeTopInset: false), GToolbar.height);
    expect(await toolbarHeight(includeTopInset: true), GToolbar.height + 44);
    expect(tester.takeException(), isNull);
  });
}
