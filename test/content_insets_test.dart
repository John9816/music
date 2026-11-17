import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:duck_music/core/services/content_insets.dart';
import 'package:duck_music/widgets/glass.dart' show topSystemInset;

void main() {
  group('ContentInsets.effectiveTop', () {
    test('原生值更大时取原生值（补足挖孔）', () {
      expect(ContentInsets.effectiveTop(20, 44), 44);
    });

    test('Flutter 值更大或相等时保持 Flutter 值（只补不覆盖）', () {
      expect(ContentInsets.effectiveTop(44, 20), 44);
      expect(ContentInsets.effectiveTop(28, 28), 28);
    });

    test('原生值为 0（未取到）时完全沿用 Flutter 值', () {
      expect(ContentInsets.effectiveTop(24, 0), 24);
    });
  });

  group('ContentInsets.resolve', () {
    test('nativeTop 更大时只抬高 top，其它三边保持不变', () {
      const data = MediaQueryData(
        padding: EdgeInsets.fromLTRB(8, 20, 12, 16),
        viewPadding: EdgeInsets.fromLTRB(8, 20, 12, 16),
      );
      final resolved = ContentInsets.resolve(data, 44);

      expect(resolved.padding.top, 44);
      expect(resolved.padding.left, 8);
      expect(resolved.padding.right, 12);
      expect(resolved.padding.bottom, 16);
      // viewPadding.top 同步抬高，避免 SafeArea 依赖它时算少。
      expect(resolved.viewPadding.top, 44);
    });

    test('nativeTop 不更大时返回原对象，避免无谓的 MediaQuery 广播', () {
      const data = MediaQueryData(padding: EdgeInsets.only(top: 44));
      expect(ContentInsets.resolve(data, 20), same(data));
      expect(ContentInsets.resolve(data, 44), same(data));
    });
  });

  group('ContentInsets 读取语义', () {
    testWidgets('topOf 读取当前 MediaQuery.padding.top', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(top: 30)),
          child: Builder(builder: (context) {
            final value = ContentInsets.topOf(context);
            return Text('$value', textDirection: TextDirection.ltr);
          }),
        ),
      );
      expect(find.text('30.0'), findsOneWidget);
    });

    testWidgets('topSystemInset 与 topOf 同源', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(top: 26)),
          child: Builder(builder: (context) {
            return Text(
              '${topSystemInset(context)}/${ContentInsets.topOf(context)}',
              textDirection: TextDirection.ltr,
            );
          }),
        ),
      );
      expect(find.text('26.0/26.0'), findsOneWidget);
    });

    testWidgets('被 SafeArea 消费后读到 0，不双重避让', (tester) async {
      // SafeArea 会把已消费的 inset 从子树 MediaQuery 里移除，子树读到的
      // top 恒为 0——头部组件因此可以无条件叠加。
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(top: 40)),
          child: SafeArea(
            top: true,
            bottom: false,
            child: Builder(builder: (context) {
              return Text(
                '${ContentInsets.topOf(context)}',
                textDirection: TextDirection.ltr,
              );
            }),
          ),
        ),
      );
      expect(find.text('0.0'), findsOneWidget);
    });

    testWidgets('of() 返回顶部与 viewInsets 的快照', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            padding: EdgeInsets.fromLTRB(8, 22, 12, 16),
            viewInsets: EdgeInsets.only(top: 5),
          ),
          child: Builder(builder: (context) {
            final insets = ContentInsets.of(context);
            return Text(
              '${insets.top},${insets.left},${insets.right},${insets.bottom},${insets.viewTop}',
              textDirection: TextDirection.ltr,
            );
          }),
        ),
      );
      expect(find.text('22.0,8.0,12.0,16.0,5.0'), findsOneWidget);
    });

    testWidgets('of() 两次读取的值相等且 hashCode 一致', (tester) async {
      late ContentInsets first;
      late ContentInsets second;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(top: 18)),
          child: Builder(builder: (context) {
            first = ContentInsets.of(context);
            second = ContentInsets.of(context);
            return const SizedBox.shrink();
          }),
        ),
      );
      expect(first, equals(second));
      expect(first.hashCode, second.hashCode);
    });
  });
}
