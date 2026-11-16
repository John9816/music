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

    // fadeStart 之前：底色全透、标题不可见。
    expect(titleOpacity(tester), 0);
    expect(fillAlpha(tester), 0);

    // 走到 fadeStart 与 fadeEnd 之间：底色已经起来，标题还没开始淡入。
    controller.jumpTo(40);
    await tester.pump();
    final midFill = fillAlpha(tester);
    expect(midFill, greaterThan(0));
    expect(midFill, lessThan(1));
    expect(titleOpacity(tester), 0);

    // fadeEnd 之后：完全变实，标题显形。
    controller.jumpTo(100);
    await tester.pump();
    expect(fillAlpha(tester), greaterThan(midFill));
    expect(titleOpacity(tester), 1);

    // 继续往下滚不再变化，避免 overscroll 把 alpha 推出区间。
    controller.jumpTo(240);
    await tester.pump();
    expect(fillAlpha(tester), lessThanOrEqualTo(1));
    expect(titleOpacity(tester), 1);
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
    expect(titleOpacity(tester), 0);
  });

  testWidgets('状态栏图标跟随底色明暗', (tester) async {
    SystemUiOverlayStyle? dark;
    SystemUiOverlayStyle? light;

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: Builder(builder: (context) {
        dark = systemOverlayStyleFor(context);
        return const SizedBox.shrink();
      }),
    ));
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.light),
      home: Builder(builder: (context) {
        light = systemOverlayStyleFor(context);
        return const SizedBox.shrink();
      }),
    ));

    // 深色底配白图标，浅色底配黑图标；iOS 的语义相反。
    expect(dark!.statusBarIconBrightness, Brightness.light);
    expect(dark!.statusBarBrightness, Brightness.dark);
    expect(light!.statusBarIconBrightness, Brightness.dark);
    expect(light!.statusBarBrightness, Brightness.light);
    expect(dark!.statusBarColor, Colors.transparent);
  });
}
