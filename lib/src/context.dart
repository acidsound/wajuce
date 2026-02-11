import 'dart:typed_data';

import 'audio_buffer.dart';
import 'enums.dart';
import 'nodes/audio_destination_node.dart';
import 'nodes/gain_node.dart';
import 'nodes/oscillator_node.dart';
import 'nodes/biquad_filter_node.dart';
import 'nodes/dynamics_compressor_node.dart';
import 'nodes/delay_node.dart';
import 'nodes/buffer_source_node.dart';
import 'nodes/analyser_node.dart';
import 'nodes/stereo_panner_node.dart';
import 'nodes/wave_shaper_node.dart';
import 'worklet/wa_worklet.dart';
import 'worklet/wa_worklet_node.dart';
import 'backend/backend.dart' as backend;

/// The main audio context. Mirrors Web Audio API AudioContext.
///
/// ```dart
/// final ctx = WAContext();
/// await ctx.resume();
///
/// final osc = ctx.createOscillator();
/// osc.frequency.value = 440;
/// osc.connect(ctx.destination);
/// osc.start();
/// ```
class WAContext {
  late final int _ctxId;
  late final WADestinationNode _destination;
  late final WAWorklet _worklet;

  /// Creates a new AudioContext.
  WAContext({int sampleRate = 44100, int bufferSize = 512}) {
    _ctxId = backend.contextCreate(sampleRate, bufferSize);
    final destId = backend.contextGetDestinationId(_ctxId);
    _destination = WADestinationNode(nodeId: destId, contextId: _ctxId);
    _worklet = WAWorklet(contextId: _ctxId, sampleRate: sampleRate);
  }

  /// Internal constructor for subclasses (OfflineAudioContext).
  WAContext.fromId(this._ctxId) {
    _worklet = WAWorklet(contextId: _ctxId);
    final destId = backend.contextGetDestinationId(_ctxId);
    _destination = WADestinationNode(nodeId: destId, contextId: _ctxId);
  }

  /// The context ID (internal).
  int get contextId => _ctxId;

  /// The output destination node.
  WADestinationNode get destination => _destination;

  /// Current audio time in seconds.
  double get currentTime => backend.contextGetTime(_ctxId);

  /// The sample rate of this context.
  double get sampleRate => backend.contextGetSampleRate(_ctxId);

  /// The current state of the context.
  WAAudioContextState get state {
    final s = backend.contextGetState(_ctxId);
    switch (s) {
      case 0:
        return WAAudioContextState.suspended;
      case 1:
        return WAAudioContextState.running;
      default:
        return WAAudioContextState.closed;
    }
  }

  /// The AudioWorklet interface for registering processors.
  WAWorklet get audioWorklet => _worklet;

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  /// Resume audio processing.
  Future<void> resume() async => backend.contextResume(_ctxId);

  /// Suspend audio processing.
  Future<void> suspend() async => backend.contextSuspend(_ctxId);

  /// Close the context and release resources.
  Future<void> close() async {
    backend.contextClose(_ctxId);
    await _worklet.close();
  }

  // -------------------------------------------------------------------------
  // Node Factory Methods
  // -------------------------------------------------------------------------

  /// Create a GainNode.
  WAGainNode createGain() {
    final id = backend.createGain(_ctxId);
    return WAGainNode(nodeId: id, contextId: _ctxId);
  }

  /// Create an OscillatorNode.
  WAOscillatorNode createOscillator() {
    final id = backend.createOscillator(_ctxId);
    return WAOscillatorNode(nodeId: id, contextId: _ctxId);
  }

  /// Create a BiquadFilterNode.
  WABiquadFilterNode createBiquadFilter() {
    final id = backend.createBiquadFilter(_ctxId);
    return WABiquadFilterNode(nodeId: id, contextId: _ctxId);
  }

  /// Create a DynamicsCompressorNode.
  WADynamicsCompressorNode createDynamicsCompressor() {
    final id = backend.createCompressor(_ctxId);
    return WADynamicsCompressorNode(nodeId: id, contextId: _ctxId);
  }

  /// Create a DelayNode with the given maximum delay time.
  WADelayNode createDelay([double maxDelayTime = 1.0]) {
    final id = backend.createDelay(_ctxId, maxDelayTime);
    return WADelayNode(
        nodeId: id, contextId: _ctxId, maxDelayTime: maxDelayTime);
  }

  /// Create an AudioBufferSourceNode.
  WABufferSourceNode createBufferSource() {
    final id = backend.createBufferSource(_ctxId);
    return WABufferSourceNode(nodeId: id, contextId: _ctxId);
  }

  /// Create an AnalyserNode.
  WAAnalyserNode createAnalyser() {
    final id = backend.createAnalyser(_ctxId);
    return WAAnalyserNode(nodeId: id, contextId: _ctxId);
  }

  /// Create a StereoPannerNode.
  WAStereoPannerNode createStereoPanner() {
    final id = backend.createStereoPanner(_ctxId);
    return WAStereoPannerNode(nodeId: id, contextId: _ctxId);
  }

  /// Create a WaveShaperNode.
  WAWaveShaperNode createWaveShaper() {
    final id = backend.createWaveShaper(_ctxId);
    return WAWaveShaperNode(nodeId: id, contextId: _ctxId);
  }

  /// Create an AudioWorkletNode.
  WAWorkletNode createWorkletNode(String processorName,
      {Map<String, double> parameterDefaults = const {}}) {
    final nodeId = _createNodeId();
    return WAWorkletNode(
      nodeId: nodeId,
      contextId: _ctxId,
      processorName: processorName,
      worklet: _worklet,
      parameterDefaults: parameterDefaults,
    );
  }

  int _createNodeId() {
    // We use a gain node as a proxy to get a valid native ID for the bridge
    return backend.createGain(_ctxId);
  }


  /// Create an AudioBuffer.
  WABuffer createBuffer(int numberOfChannels, int length, double sampleRate) {
    return WABuffer(
      numberOfChannels: numberOfChannels,
      length: length,
      sampleRate: sampleRate,
    );
  }

  /// Decode audio data from a byte array.
  Future<WABuffer> decodeAudioData(Uint8List audioData) {
    return backend.decodeAudioData(_ctxId, audioData);
  }
}
