import 'dart:typed_data';
import 'package:wajuce/wajuce.dart';

const String _clockProcessorName = 'clock-processor';

final bool _clockWorkletModuleDefined = WAWorkletModules.define(
  _clockProcessorName,
  (registrar) {
    registrar.registerProcessor(
      _clockProcessorName,
      () => ClockProcessor(),
    );
  },
);

Future<void> loadClockWorkletModule(WAContext context) async {
  // Touch top-level module registration so import intent is explicit.
  if (!_clockWorkletModuleDefined) {
    // Already defined by another import path; nothing to do.
  }
  await context.audioWorklet.addModule(_clockProcessorName);
}

WAWorkletNode createClockWorkletNode(WAContext context,
    {Map<String, double> parameterDefaults = const {}}) {
  return context.createWorkletNode(
    _clockProcessorName,
    parameterDefaults: parameterDefaults,
  );
}

class ClockProcessor extends WAWorkletProcessor {
  double _sampleRate = 44100.0;
  double _contextStartTime = 0.0;
  double _bpm = 120.0;
  bool _running = false;
  int _currentFrame = 0;
  double _nextTickFrame = 0.0;
  double _lastTickFrame = 0.0;
  int _step = 0;

  ClockProcessor() : super(name: _clockProcessorName);

  @override
  void init([Map<String, double> options = const {}]) {
    if (options.containsKey('sampleRate')) {
      _sampleRate = options['sampleRate']!;
    }

    // Listen for messages from main thread
    port.onMessage = (data) {
      if (data is Map) {
        if (data['type'] == 'start') {
          _running = true;
          _currentFrame = 0;
          _step = 0;
          _nextTickFrame = 0.0;
          _lastTickFrame = 0.0;
          _contextStartTime = (data['contextTime'] as num?)?.toDouble() ?? 0.0;
        } else if (data['type'] == 'stop') {
          _running = false;
        } else if (data['type'] == 'bpm') {
          final nextBpm = (data['value'] as num?)?.toDouble() ?? _bpm;
          final oldFramesPer16th = _framesPer16th;
          _bpm = nextBpm > 1 ? nextBpm : 1.0;
          if (_running) {
            final currentFrame = _currentFrame.toDouble();
            final newFramesPer16th = _framesPer16th;

            if (oldFramesPer16th > 0 && newFramesPer16th > 0) {
              // Keep musical phase continuous across BPM changes.
              double elapsedInStep = currentFrame - _lastTickFrame;
              if (elapsedInStep < 0) elapsedInStep = 0;
              if (elapsedInStep > oldFramesPer16th) {
                elapsedInStep = oldFramesPer16th;
              }

              final phase = elapsedInStep / oldFramesPer16th;
              double remaining = 1.0 - phase;
              if (remaining < 0) remaining = 0;
              if (remaining > 1) remaining = 1;

              _nextTickFrame = currentFrame + (remaining * newFramesPer16th);
            } else {
              _nextTickFrame = currentFrame + newFramesPer16th;
            }
          }
        } else if (data['type'] == 'syncTime') {
          final syncContextTime =
              (data['contextTime'] as num?)?.toDouble() ?? _contextStartTime;
          // Keep frame->contextTime mapping continuous when syncing mid-play.
          _contextStartTime = syncContextTime - (_currentFrame / _sampleRate);
        }
      }
    };
  }

  double get _framesPer16th => (15.0 / _bpm) * _sampleRate;

  @override
  bool process(
    List<List<Float32List>> inputs,
    List<List<Float32List>> outputs,
    Map<String, Float32List> parameters,
  ) {
    if (!_running) return true;

    int framesToProcess = 128;
    if (inputs.isNotEmpty && inputs[0].isNotEmpty) {
      framesToProcess = inputs[0][0].length;
    } else if (outputs.isNotEmpty && outputs[0].isNotEmpty) {
      framesToProcess = outputs[0][0].length;
    }

    final blockStartFrame = _currentFrame.toDouble();
    final blockEndFrame = blockStartFrame + framesToProcess;
    final framesPer16th = _framesPer16th;
    if (framesPer16th <= 0) {
      _currentFrame += framesToProcess;
      return true;
    }

    // Emit every tick that falls inside this render quantum.
    while (_nextTickFrame < blockEndFrame) {
      if (_nextTickFrame >= blockStartFrame) {
        final scheduledTime =
            _contextStartTime + (_nextTickFrame / _sampleRate);
        port.postMessage({
          'type': 'tick',
          'step': _step,
          'time': scheduledTime,
        });
        _lastTickFrame = _nextTickFrame;
        _step = (_step + 1) % 16;
      }
      _nextTickFrame += framesPer16th;
    }

    _currentFrame += framesToProcess;

    return true;
  }
}
