import 'package:duck_music/core/auth/auth_controller.dart';
import 'package:duck_music/features/tools/ai_draw_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('mobile AI workbench stacks canvas and expandable controls',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(const AiDrawView()));
    await tester.pump();

    expect(find.byKey(const Key('ai-prompt-field')), findsOneWidget);
    expect(find.text('生成参数'), findsOneWidget);
    expect(find.byKey(const Key('ai-size-field')), findsNothing);

    await tester.tap(find.text('生成参数'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ai-size-field')), findsOneWidget);
    expect(find.byKey(const Key('ai-count-field')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop AI workbench keeps controls beside canvas',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(const AiDrawView()));
    await tester.pump();

    expect(find.byKey(const Key('ai-size-field')), findsOneWidget);
    expect(find.byKey(const Key('ai-count-field')), findsOneWidget);

    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ai-source-picker')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _app(Widget home) {
  return ChangeNotifierProvider<AuthController>(
    create: (_) => AuthController(),
    child: MaterialApp(theme: ThemeData.light(), home: home),
  );
}
