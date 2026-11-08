import 'dart:async';

import 'package:duck_music/core/services/audio_spectrum_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const method = MethodChannel('test.duckmusic/spectrum');
  const events = EventChannel('test.duckmusic/spectrum/frames');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late AudioSpectrumService service;
  late List<MethodCall> calls;
  late int requestId;
  late Future<Object?> Function(MethodCall) respond;

  Future<void> event(Object value) async {
    await messenger.handlePlatformMessage(
      events.name,
      const StandardMethodCodec().encodeSuccessEnvelope(value),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);
  }

  setUp(() {
    calls = [];
    requestId = 0;
    respond = (call) async {
      if (call.method == 'start') {
        requestId = (call.arguments as Map)['requestId'] as int;
        return {'status': 'active'};
      }
      return null;
    };
    messenger.setMockMethodCallHandler(method, (call) {
      calls.add(call);
      return respond(call);
    });
    messenger.setMockMethodCallHandler(
      MethodChannel(events.name),
      (_) async => null,
    );
    service = AudioSpectrumService(channel: method, eventChannel: events);
  });

  tearDown(() async {
    service.dispose();
    await Future<void>.delayed(Duration.zero);
    messenger.setMockMethodCallHandler(method, null);
    messenger.setMockMethodCallHandler(MethodChannel(events.name), null);
  });

  test('requires explicit permission intent before requesting capture',
      () async {
    respond = (call) async {
      if (call.method != 'start') return null;
      final arguments = call.arguments as Map;
      expect(arguments['sessionId'], 73);
      return {
        'status': arguments['requestPermission'] == true
            ? 'active'
            : 'permissionRequired',
      };
    };

    expect(await service.start(73), isFalse);
    expect(service.status, AudioSpectrumStatus.permissionRequired);
    expect((calls.single.arguments as Map)['requestPermission'], isFalse);
    expect(await service.start(73, requestPermission: true), isTrue);
    expect(service.status, AudioSpectrumStatus.active);
  });

  test('permission refusal stays recoverable and never claims capture',
      () async {
    respond = (_) async => {'status': 'permissionRequired'};
    expect(await service.start(73, requestPermission: true), isFalse);
    expect(service.status, AudioSpectrumStatus.permissionRequired);
  });

  test('rejects output mix session zero before creating a visualizer',
      () async {
    expect(await service.start(0, requestPermission: true), isFalse);
    expect(service.status, AudioSpectrumStatus.unavailable);
    await Future<void>.delayed(Duration.zero);
    expect(calls.where((call) => call.method == 'start'), isEmpty);
  });

  test('normalizes valid frames and ignores malformed or stale frames',
      () async {
    final received = <List<double>>[];
    final sub = service.frames.listen(received.add);
    addTearDown(sub.cancel);
    await service.start(73);
    final values = List<num>.filled(32, 0);
    values[0] = -2;
    values[1] = .75;
    values[2] = 9;
    await event({'requestId': requestId, 'bands': values});
    expect(received.single.take(3), [0.0, .75, 1.0]);
    await event({'requestId': requestId - 1, 'bands': values});
    await event({
      'requestId': requestId,
      'bands': [1, 2]
    });
    await event({
      'requestId': requestId,
      'bands': List<double>.filled(32, double.nan),
    });
    expect(received, hasLength(1));
  });

  test('stop defeats a late successful start and discards later frames',
      () async {
    final pending = Completer<Object?>();
    respond = (call) async {
      if (call.method == 'start') {
        requestId = (call.arguments as Map)['requestId'] as int;
        return pending.future;
      }
      return null;
    };
    final received = <List<double>>[];
    final sub = service.frames.listen(received.add);
    addTearDown(sub.cancel);
    final start = service.start(73);
    await Future<void>.delayed(Duration.zero);
    await service.stop();
    pending.complete({'status': 'active'});
    expect(await start, isFalse);
    expect(service.status, AudioSpectrumStatus.idle);
    expect(calls.last.method, 'stop');
    await event({'requestId': requestId, 'bands': List.filled(32, .9)});
    expect(received.where((frame) => frame.any((v) => v > 0)), isEmpty);
  });

  test('older session response cannot overwrite a newer session', () async {
    final first = Completer<Object?>();
    respond = (call) async {
      if (call.method != 'start') return null;
      if ((call.arguments as Map)['sessionId'] == 73) return first.future;
      return {'status': 'active'};
    };
    final oldStart = service.start(73);
    await Future<void>.delayed(Duration.zero);
    expect(await service.start(91), isTrue);
    first.complete({'status': 'unavailable'});
    expect(await oldStart, isFalse);
    expect(service.status, AudioSpectrumStatus.active);
  });

  test('pause releases capture but permission dialog inactivity does not',
      () async {
    await service.start(73);
    service.didChangeAppLifecycleState(AppLifecycleState.inactive);
    await Future<void>.delayed(Duration.zero);
    expect(service.status, AudioSpectrumStatus.active);
    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(Duration.zero);
    expect(service.status, AudioSpectrumStatus.idle);
    expect(calls.last.method, 'stop');
  });

  test('missing native implementation is unavailable without throwing',
      () async {
    final errors = <FlutterErrorDetails>[];
    final previousErrorHandler = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previousErrorHandler);
    messenger.setMockMethodCallHandler(
      MethodChannel(events.name),
      (_) async => throw MissingPluginException(),
    );
    respond = (_) async => throw MissingPluginException();
    expect(await service.start(73), isFalse);
    expect(service.status, AudioSpectrumStatus.unavailable);
    await Future<void>.delayed(Duration.zero);
    await service.stop();
    expect(service.status, AudioSpectrumStatus.idle);
    service.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(errors, isEmpty);
  });

  test('native suspension clears visible bars and active state', () async {
    await service.start(73);
    final received = <List<double>>[];
    final sub = service.frames.listen(received.add);
    addTearDown(sub.cancel);
    await event({'requestId': requestId, 'status': 'idle'});
    expect(service.status, AudioSpectrumStatus.idle);
    expect(received.single, everyElement(0));
  });

  test('retained service reconnects frames after Android activity recreation',
      () async {
    var nativeListening = false;
    var listens = 0;
    messenger.setMockMethodCallHandler(MethodChannel(events.name),
        (call) async {
      if (call.method == 'listen') {
        nativeListening = true;
        listens++;
      } else if (call.method == 'cancel') {
        if (!nativeListening) {
          throw PlatformException(code: 'error', message: 'No active stream');
        }
        nativeListening = false;
      }
      return null;
    });
    final received = <List<double>>[];
    final sub = service.frames.listen(received.add);
    addTearDown(sub.cancel);
    await service.start(73);
    if (nativeListening) {
      await event({'requestId': requestId, 'bands': List.filled(32, .2)});
    }
    expect(received.last.first, .2);

    // The engine and service survive, but the replacement Activity has no
    // native EventSink. Cancelling its predecessor is legitimately a no-op.
    nativeListening = false;
    await service.stop();
    expect(await service.start(91), isTrue);
    if (nativeListening) {
      await event({'requestId': requestId, 'bands': List.filled(32, .8)});
    }
    expect(received.last.first, .8);
    expect(listens, 2);
  });

  test('restart waits for old cancellation before creating a new capture',
      () async {
    final cancellation = Completer<Object?>();
    var cancels = 0;
    messenger.setMockMethodCallHandler(MethodChannel(events.name),
        (call) async {
      if (call.method == 'cancel' && cancels++ == 0) {
        return cancellation.future;
      }
      return null;
    });
    await service.start(73);
    final stopping = service.stop();
    final restarting = service.start(91);
    await Future<void>.delayed(Duration.zero);
    expect(calls.where((call) => call.method == 'start'), hasLength(1));
    cancellation.complete(null);
    await stopping;
    expect(await restarting, isTrue);
    expect(service.status, AudioSpectrumStatus.active);
  });

  test('missing frame handler is recoverable without a global Flutter error',
      () async {
    final errors = <FlutterErrorDetails>[];
    final previousErrorHandler = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previousErrorHandler);
    messenger.setMockMethodCallHandler(MethodChannel(events.name),
        (_) async => throw MissingPluginException());
    expect(await service.start(73), isFalse);
    expect(service.status, AudioSpectrumStatus.unavailable);
    await Future<void>.delayed(Duration.zero);
    expect(errors, isEmpty);

    messenger.setMockMethodCallHandler(
        MethodChannel(events.name), (_) async => null);
    expect(await service.start(91), isTrue);
    expect(service.status, AudioSpectrumStatus.active);
  });

  test('native idle snapshot during listen cannot leave capture active',
      () async {
    messenger.setMockMethodCallHandler(MethodChannel(events.name),
        (call) async {
      if (call.method == 'listen') {
        await event({'requestId': requestId, 'status': 'idle'});
      }
      return null;
    });
    expect(await service.start(73), isFalse);
    expect(service.status, AudioSpectrumStatus.idle);
  });

  test('native stream errors stop capture and clear the last frame', () async {
    final received = <List<double>>[];
    final sub = service.frames.listen(received.add);
    addTearDown(sub.cancel);
    await service.start(73);
    await event({'requestId': requestId, 'bands': List.filled(32, .8)});
    await messenger.handlePlatformMessage(
      events.name,
      const StandardMethodCodec().encodeErrorEnvelope(
          code: 'permissionRequired', message: 'Capture permission revoked'),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);
    expect(service.status, AudioSpectrumStatus.permissionRequired);
    expect(received.last, everyElement(0));
    expect(calls.last.method, 'stop');
    await event({'requestId': requestId, 'bands': List.filled(32, .9)});
    expect(received.last, everyElement(0));
  });

  test('suspension during start wins over a late active reply', () async {
    await service.start(60);
    final pending = Completer<Object?>();
    respond = (call) async {
      if (call.method != 'start') return null;
      requestId = (call.arguments as Map)['requestId'] as int;
      return pending.future;
    };
    final start = service.start(73);
    await Future<void>.delayed(Duration.zero);
    await event({'requestId': requestId, 'status': 'idle'});
    pending.complete({'status': 'active'});
    expect(await start, isFalse);
    expect(service.status, AudioSpectrumStatus.idle);
  });

  test('disposal cancels a pending start without post-disposal notifications',
      () async {
    final pending = Completer<Object?>();
    respond = (call) async => call.method == 'start' ? pending.future : null;
    final start = service.start(73);
    await Future<void>.delayed(Duration.zero);
    service.dispose();
    pending.complete({'status': 'active'});
    expect(await start, isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(calls.last.method, 'stop');
  });
}
