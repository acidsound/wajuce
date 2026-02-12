import 'dart:typed_data';
import 'package:wajuce/wajuce.dart';

class ClockProcessor extends WAWorkletProcessor {
  double _sampleRate = 44100.0;
  double _bpm = 120.0;
  bool _running = false;
  int _currentFrame = 0;
  double _nextTickFrame = 0.0;
  int _step = 0;

  ClockProcessor() : super(name: 'clock-processor');

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
          _scheduleNextTick();
        } else if (data['type'] == 'stop') {
          _running = false;
        } else if (data['type'] == 'bpm') {
          _bpm = (data['value'] as num).toDouble();
          _scheduleNextTick(reset: false);
        }
      }
    };
  }

  void _scheduleNextTick({bool reset = true}) {
    if (reset) {
       _nextTickFrame = _currentFrame.toDouble();
    } else {
       // Recalculate based on new BPM if needed, but for now simple
    }
  }

  @override
  bool process(
    List<List<Float32List>> inputs,
    List<List<Float32List>> outputs,
    Map<String, Float32List> parameters,
  ) {
    if (!_running) return true;

    // Process 128 frames
    int framesToProcess = 128; // Standard Web Audio block size
    // In wajuce standard block is 128? Or variable?
    // WAWorkletProcessor implementation implies it's called per block.
    // Let's assume block size logic in AudioIsolate handles this.
    // Actually, inputs[0][0].length tells us the block size.
    if (inputs.isNotEmpty && inputs[0].isNotEmpty) {
      framesToProcess = inputs[0][0].length;
    } else if (outputs.isNotEmpty && outputs[0].isNotEmpty) {
      framesToProcess = outputs[0][0].length;
    }

    // Samples per 16th note
    // 1 minute = 60 seconds
    // 1 beat = 60/BPM seconds
    // 16th note = 1/4 beat = 15/BPM seconds
    // Frames per 16th = (15/BPM) * SampleRate
    double framesPer16th = (15.0 / _bpm) * _sampleRate;

    // Check if we hit the next tick within this block
    if (_currentFrame + framesToProcess >= _nextTickFrame) {
      // It's time!
      // Send message to main thread
      port.postMessage({'type': 'tick', 'step': _step});
      _step = (_step + 1) % 16;
      _nextTickFrame += framesPer16th;
      
      // Handle multiple ticks in one block? (Very fast BPM or large block)
      // For now assume standard BPM and block size (128 samples is extremely short ~3ms)
      // chances of >1 tick in 3ms is low unless BPM > 5000
    }

    _currentFrame += framesToProcess;

    return true;
  }
}
