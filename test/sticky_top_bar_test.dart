import 'package:duck_music/widgets/sticky_top_bar.dart';
import 'package:duck_music/widgets/system_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 顶部从「滚动内容里的大标题」过渡到「固定的居中标题」，靠的是同一个滚动
/// 进度驱动三条曲线。这里锁定三件事：进度为 0 时完全透明且不吃手势、进度到顶
/// 时标题完全显形、底色 alpha 单调递增。
void main() {
  Widget harness(ScrollController controller) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            ListView.builder(
              controller: controller,
              itemCount: 60,
              itemBuilder: (_, i) => SizedBox(height: 60, child: Text('row$i')),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: GStickyTopBar(
                controller: controller,
                title: '探索',
                fadeStart: 20,
                fadeEnd: 100,
              ),
            ),
          ],
        ),
      ),
    );
  }

  double titleOpacity(WidgetTester tester) =>
      tester.widget<Opacity>(find.byKey(gStickyTopBarTitleKey)).opacity;

  double fillAlpha(WidgetTester tester) {
    final bar = tester.widget<Container>(find.byKey(gStickyTopBarFillKey));
    return (bar.decoration! as BoxDecoration).color!.a;
  }

  testWidgets('滚动进度驱动标题淡入与底色 alpha', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(harness(controller));
    await tester.pump();
    // 首帧布局可能带着非零的滚动位置，先归零再测起点。
    controller.jumpTo(0);
    await tester.pump();

    // fadeStart 之前：底色全透，标题还没有进入树里。
    expect(controller.offset, 0);
    expect(find.byKey(gStickyTopBarTitleKey), findsNothing);
    expect(fillAlpha(tester), 0);

    // 走到 fadeStart 与 fadeEnd 之间：底色已经起来，但还没到标题的淡入阈值。
    controller.jumpTo(30);
    await tester.pump();
    final midFill = fillAlpha(tester);
    expect(midFill, greaterThan(0));
    expect(midFill, lessThan(1));
    expect(find.byKey(gStickyTopBarTitleKey), findsNothing);

    // fadeEnd 之后：完全变实，标题显形。
    controller.jumpTo(100);
    await tester.pump();
    expect(fillAlpha(tester), greaterThan(midFill));
    expect(titleOpacity(tester), closeTo(1, 1e-6));

    // 继续往下滚不再变化，避免 overscroll 把 alpha 推出区间。
    controller.jumpTo(240);
    await tester.pump();
    expect(fillAlpha(tester), lessThanOrEqualTo(1));
    expect(titleOpacity(tester), closeTo(1, 1e-6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('进度为 0 时不参与命中测试，顶部手势照常落到列表', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(harness(controller));

    await tester.drag(find.text('row0'), const Offset(0, -120));
    await tester.pump();

    expect(controller.offset, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('控制器未挂载时不抛异常', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Stack(
        children: [
          const SizedBox.expand(),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: GStickyTopBar(controller: controller, title: '探索'),
          ),
        ],
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.byKey(gStickyTopBarTitleKey), findsNothing);
  });

  testWidgets('状态栏图标跟随底色明暗', (tester) async {
    SystemUiOverlayStyle? onDark;
    SystemUiOverlayStyle? onLight;

    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        // 明确给出底色，不依赖各版本 ThemeData 的默认 surface 取值。
        onDark = systemOverlayStyleFor(context,
            background: const Color(0xFF0A0A0B));
        onLight = systemOverlayStyleFor(context,
            background: const Color(0xFFF7F8FA));
        return const SizedBox.shrink();
      }),
    ));

    // 深色底配白图标，浅色底配黑图标；iOS 的语义相反。
    expect(onDark!.statusBarIconBrightness, Brightness.light);
    expect(onDark!.statusBarBrightness, Brightness.dark);
    expect(onLight!.statusBarIconBrightness, Brightness.dark);
    expect(onLight!.statusBarBrightness, Brightness.light);
    expect(onDark!.statusBarColor, Colors.transparent);
    expect(onDark!.systemNavigationBarContrastEnforced, false);
  });
}
