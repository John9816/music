import 'package:duck_music/core/api/ai_draw_api.dart';
import 'package:duck_music/core/auth/auth_controller.dart';
import 'package:duck_music/features/tools/ai_draw_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('mobile AI workbench uses compact tabs and a parameter sheet',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(const AiDrawView()));
    await tester.pump();

    expect(find.byKey(const Key('ai-prompt-field')), findsOneWidget);
    expect(find.text('广场'), findsOneWidget);
    expect(find.byKey(const Key('ai-mobile-parameters')), findsOneWidget);
    expect(find.byKey(const Key('ai-size-field')), findsNothing);
    expect(find.byKey(const Key('ai-bottom-queue')), findsNothing);

    await tester.tap(find.byKey(const Key('ai-mobile-parameters')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ai-size-field')), findsOneWidget);
    expect(find.byKey(const Key('ai-count-field')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile AI workbench opens the public image plaza',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(AiDrawView(api: _FakeAiDrawApi())));
    await tester.pump();
    await tester.tap(find.byKey(const Key('ai-mode-plaza')));
    await tester.pumpAndSettle();

    expect(find.text('分享广场'), findsOneWidget);
    expect(find.byKey(const Key('ai-shared-image-88')), findsOneWidget);

    await tester.tap(find.byKey(const Key('ai-shared-image-88')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ai-image-viewer')), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byTooltip('下载图片'), findsOneWidget);
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

class _FakeAiDrawApi extends AiDrawApi {
  @override
  Future<AiDrawPage<AiDrawHistoryItem>> shared({
    int page = 0,
    int size = 20,
  }) async {
    return AiDrawPage(
      items: const [
        AiDrawHistoryItem(
          id: 88,
          prompt: '雨夜唱片封面',
          imageUrl:
              'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL7WQAAAABJRU5ErkJggg==',
          size: '1024x1024',
          isShared: true,
        ),
      ],
      total: 1,
      page: page,
      size: size,
    );
  }
}

Widget _app(Widget home) {
  return ChangeNotifierProvider<AuthController>(
    create: (_) => AuthController(),
    child: MaterialApp(theme: ThemeData.light(), home: home),
  );
}
