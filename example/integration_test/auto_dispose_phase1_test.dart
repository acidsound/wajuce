import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wajuce/wajuce.dart';

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 3),
  Duration step = const Duration(milliseconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(step);
  }
  if (!predicate()) {
    throw TimeoutException('Condition was not met in time.');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('scheduled sources auto-dispose and last stop wins',
      (tester) async {
    final ctx = WAContext();
    await ctx.resume();

    try {
      // Oscillator: last stop call should win over an older later stop.
      final osc = ctx.createOscillator();
      final oscGain = ctx.createGain();
      oscGain.gain.value = 0.0;
      osc.connect(oscGain);
      oscGain.connect(ctx.destination);

      final oscEnded = Completer<void>();
      osc.onEnded = () {
        if (!oscEnded.isCompleted) {
          oscEnded.complete();
        }
      };

      final oscStartAt = ctx.currentTime + 0.02;
      osc.start(oscStartAt);
      osc.stop(ctx.currentTime + 1.0);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      osc.stop(ctx.currentTime + 0.06);
      await oscEnded.future.timeout(const Duration(milliseconds: 800));

      // ConstantSource: stop should trigger onEnded + auto-dispose.
      final constant = ctx.createConstantSource();
      final constantGain = ctx.createGain();
      constantGain.gain.value = 0.0;
      constant.connect(constantGain);
      constantGain.connect(ctx.destination);

      final constantEnded = Completer<void>();
      constant.onEnded = () {
        if (!constantEnded.isCompleted) {
          constantEnded.complete();
        }
      };

      final constantStartAt = ctx.currentTime + 0.02;
      constant.start(constantStartAt);
      constant.stop(constantStartAt + 0.05);
      await constantEnded.future.timeout(const Duration(seconds: 2));

      // BufferSource: natural end should trigger onEnded when not looping.
      final oneShot = ctx.createBufferSource();
      final oneShotGain = ctx.createGain();
      oneShotGain.gain.value = 0.0;
      oneShot.connect(oneShotGain);
      oneShotGain.connect(ctx.destination);

      final sampleRate = ctx.sampleRate;
      final length = (sampleRate * 0.08).round();
      final buffer = ctx.createBuffer(1, length, sampleRate);
      oneShot.buffer = buffer;

      final oneShotEnded = Completer<void>();
      oneShot.onEnded = () {
        if (!oneShotEnded.isCompleted) {
          oneShotEnded.complete();
        }
      };

      oneShot.start(ctx.currentTime + 0.02);
      await oneShotEnded.future.timeout(const Duration(seconds: 2));

      // Looping source should not auto-end until explicit stop.
      final looping = ctx.createBufferSource();
      final loopingGain = ctx.createGain();
      loopingGain.gain.value = 0.0;
      looping.connect(loopingGain);
      loopingGain.connect(ctx.destination);
      looping.buffer = buffer;
      looping.loop = true;

      var loopEnded = false;
      looping.onEnded = () {
        loopEnded = true;
      };

      looping.start(ctx.currentTime + 0.02);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(loopEnded, isFalse);

      looping.stop(ctx.currentTime + 0.05);
      await _waitUntil(() => loopEnded, timeout: const Duration(seconds: 2));
      expect(loopEnded, isTrue);
    } finally {
      await ctx.close();
    }
  });

  testWidgets('worklet ended cleanup is idempotent', (tester) async {
    final worklet = WAWorklet(contextId: 0);
    var disposeCount = 0;

    worklet.registerNodeDisposer(4242, () {
      disposeCount += 1;
      worklet.removeNode(4242);
    });

    worklet.isolateManager.onNodeEnded?.call(4242);
    worklet.isolateManager.onNodeEnded?.call(4242);
    worklet.removeNode(4242);

    expect(disposeCount, 1);
    await worklet.close();
  });

  testWidgets('connectOwned cascades only owned nodes', (tester) async {
    final ctx = WAContext();
    await ctx.resume();

    try {
      final master = ctx.createGain();
      master.gain.value = 0.0;
      master.connect(ctx.destination);

      final osc = ctx.createOscillator();
      final filter = ctx.createBiquadFilter();
      final voiceGain = ctx.createGain();
      voiceGain.gain.value = 0.0;

      osc.connectOwned(filter);
      filter.connectOwned(voiceGain);
      voiceGain.connect(master);

      final ended = Completer<void>();
      osc.onEnded = () {
        if (!ended.isCompleted) {
          ended.complete();
        }
      };

      final startAt = ctx.currentTime + 0.02;
      osc.start(startAt);
      osc.stop(startAt + 0.05);
      await ended.future.timeout(const Duration(seconds: 2));

      expect(osc.isDisposed, isTrue);
      expect(filter.isDisposed, isTrue);
      expect(voiceGain.isDisposed, isTrue);
      expect(master.isDisposed, isFalse);
      expect(ctx.destination.isDisposed, isFalse);

      final probe = ctx.createGain();
      probe.gain.value = 0.0;
      probe.connect(master);
      expect(master.isDisposed, isFalse);
      probe.dispose();
      master.dispose();
    } finally {
      await ctx.close();
    }
  });

  testWidgets('disconnect removes owned cascade link', (tester) async {
    final ctx = WAContext();
    await ctx.resume();

    try {
      final osc = ctx.createOscillator();
      final gain = ctx.createGain();
      gain.gain.value = 0.0;
      gain.connect(ctx.destination);

      osc.connectOwned(gain);
      osc.disconnect(gain);
      osc.connect(ctx.destination);

      final ended = Completer<void>();
      osc.onEnded = () {
        if (!ended.isCompleted) {
          ended.complete();
        }
      };

      final startAt = ctx.currentTime + 0.02;
      osc.start(startAt);
      osc.stop(startAt + 0.05);
      await ended.future.timeout(const Duration(seconds: 2));

      expect(osc.isDisposed, isTrue);
      expect(gain.isDisposed, isFalse);

      gain.dispose();
    } finally {
      await ctx.close();
    }
  });
}
