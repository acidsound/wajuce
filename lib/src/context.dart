import 'dart:typed_data';

import 'audio_buffer.dart';
import 'audio_context_extras.dart';
import 'audio_listener.dart';
import 'enums.dart';
import 'nodes/audio_node.dart';
import 'nodes/audio_destination_node.dart';
import 'nodes/gain_node.dart';
import 'nodes/oscillator_node.dart';
import 'nodes/biquad_filter_node.dart';
import 'nodes/dynamics_compressor_node.dart';
import 'nodes/delay_node.dart';
import 'nodes/buffer_source_node.dart';
import 'nodes/analyser_node.dart';
import 'nodes/stereo_panner_node.dart';
import 'nodes/panner_node.dart';
import 'nodes/wave_shaper_node.dart';
import 'nodes/media_stream_nodes.dart';
import 'nodes/media_element_source_node.dart';
import 'nodes/media_stream_track_source_node.dart';
import 'nodes/channel_splitter_node.dart';
import 'nodes/channel_merger_node.dart';
import 'nodes/constant_source_node.dart';
import 'nodes/convolver_node.dart';
import 'nodes/iir_filter_node.dart';
import 'nodes/script_processor_node.dart';
import 'nodes/periodic_wave.dart';
import 'worklet/wa_worklet.dart';
import 'worklet/wa_worklet_module.dart';
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
  late final WAAudioListener _listener;
  late final WAAudioRenderCapacity _renderCapacity;
  late final WAWorklet _worklet;
  int _requestedSampleRate = 44100;
  int _requestedBufferSize = 512;
  int _requestedNumberOfChannels = 2;
  int _requestedBitDepth = 32;

  /// Creates a new AudioContext.
  WAContext(
      {int sampleRate = 44100,
      int bufferSize = 512,
      int numberOfChannels = 2}) {
    _requestedSampleRate = sampleRate;
    _requestedBufferSize = bufferSize;
    _requestedNumberOfChannels = numberOfChannels;
    _ctxId = backend.contextCreate(sampleRate, bufferSize,
        inputChannels: numberOfChannels, outputChannels: numberOfChannels);
    final destId = backend.contextGetDestinationId(_ctxId);
    _destination = WADestinationNode(
      nodeId: destId,
      contextId: _ctxId,
      maxChannelCount: backend.destinationGetMaxChannelCount(_ctxId),
    );
    _listener = WAAudioListener(nodeId: backend.contextGetListenerId(_ctxId));
    _renderCapacity = WAAudioRenderCapacity(_ctxId);
    _worklet = WAWorklet(contextId: _ctxId, sampleRate: sampleRate);
    _requestedBitDepth = backend.contextGetBitDepth(_ctxId);

    // Initialize Web AudioWorklet if on Web
    backend.webInitializeWorklet(_ctxId);
  }

  /// Internal constructor for subclasses (OfflineAudioContext).
  WAContext.fromId(this._ctxId) {
    _requestedSampleRate = backend.contextGetSampleRate(_ctxId).round();
    _requestedBitDepth = backend.contextGetBitDepth(_ctxId);
    _worklet = WAWorklet(contextId: _ctxId);
    final destId = backend.contextGetDestinationId(_ctxId);
    _destination = WADestinationNode(
      nodeId: destId,
      contextId: _ctxId,
      maxChannelCount: backend.destinationGetMaxChannelCount(_ctxId),
    );
    _listener = WAAudioListener(nodeId: backend.contextGetListenerId(_ctxId));
    _renderCapacity = WAAudioRenderCapacity(_ctxId);

    // Initialize Web AudioWorklet if on Web
    backend.webInitializeWorklet(_ctxId);
  }

  /// The context ID (internal).
  int get contextId => _ctxId;

  /// The output destination node.
  WADestinationNode get destination => _destination;

  /// The listener used by spatialized nodes.
  WAAudioListener get listener => _listener;

  /// Current audio time in seconds.
  double get currentTime => backend.contextGetTime(_ctxId);

  // Helper for generating unique node IDs for Dart-side nodes (Worklets)
  int _nextNodeId = 10000; // Start high to avoid collision with native IDs
  /// Generates a unique node ID for manual node creation.
  int createNodeId() => _nextNodeId++;

  /// The sample rate of this context.
  double get sampleRate => backend.contextGetSampleRate(_ctxId);

  /// Effective device bit depth when available.
  int get bitDepth => backend.contextGetBitDepth(_ctxId);

  /// Requested sample rate used when creating this context.
  int get requestedSampleRate => _requestedSampleRate;

  /// Requested buffer size used when creating this context.
  int get requestedBufferSize => _requestedBufferSize;

  /// Requested I/O channel count used when creating this context.
  int get requestedNumberOfChannels => _requestedNumberOfChannels;

  /// Requested bit depth preference.
  int get requestedBitDepth => _requestedBitDepth;

  /// Base processing latency (seconds) when available.
  double get baseLatency => backend.contextGetBaseLatency(_ctxId);

  /// Output device latency (seconds) when available.
  double get outputLatency => backend.contextGetOutputLatency(_ctxId);

  /// Sink identifier, when available.
  Object get sinkId => backend.contextGetSinkId(_ctxId);

  /// Render-capacity API surface.
  WAAudioRenderCapacity get renderCapacity => _renderCapacity;

  /// Output timestamp pair.
  WAAudioTimestamp getOutputTimestamp() {
    final ts = backend.contextGetOutputTimestamp(_ctxId);
    return WAAudioTimestamp(
      contextTime: ts['contextTime'] ?? currentTime,
      performanceTime: ts['performanceTime'] ?? 0.0,
    );
  }

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

  /// Ask backend to switch to a preferred device sample-rate.
  ///
  /// Returns `true` if the request was accepted by the backend/device.
  Future<bool> setPreferredSampleRate(double preferredSampleRate) async {
    if (preferredSampleRate <= 0) {
      return false;
    }
    final ok =
        backend.contextSetPreferredSampleRate(_ctxId, preferredSampleRate);
    if (ok) {
      _requestedSampleRate = preferredSampleRate.round();
    }
    return ok;
  }

  /// Ask backend to switch to a preferred device bit-depth.
  ///
  /// Not all backends/devices support changing bit-depth at runtime.
  Future<bool> setPreferredBitDepth(int preferredBitDepth) async {
    if (preferredBitDepth <= 0) {
      return false;
    }
    final ok = backend.contextSetPreferredBitDepth(_ctxId, preferredBitDepth);
    if (ok) {
      _requestedBitDepth = preferredBitDepth;
    }
    return ok;
  }

  /// Suspend audio processing.
  Future<void> suspend() async => backend.contextSuspend(_ctxId);

  /// Close the context and release resources.
  Future<void> close() async {
    _renderCapacity.stop();
    backend.contextClose(_ctxId);
    await _worklet.close();
  }

  /// Recreate this context with updated audio device preferences.
  ///
  /// This closes the current context and returns a fresh context instance.
  Future<WAContext> recreate({
    int? sampleRate,
    int? bufferSize,
    int? numberOfChannels,
    int? bitDepth,
    bool autoResume = true,
  }) async {
    final nextSampleRate = sampleRate ?? _requestedSampleRate;
    final nextBufferSize = bufferSize ?? _requestedBufferSize;
    final nextChannels = numberOfChannels ?? _requestedNumberOfChannels;
    final nextBitDepth = bitDepth ?? _requestedBitDepth;

    await close();

    final next = WAContext(
      sampleRate: nextSampleRate,
      bufferSize: nextBufferSize,
      numberOfChannels: nextChannels,
    );
    if (autoResume) {
      await next.resume();
      await next.setPreferredSampleRate(nextSampleRate.toDouble());
      await next.setPreferredBitDepth(nextBitDepth);
    }
    return next;
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

  /// Create a PannerNode (3D spatial panner).
  WAPannerNode createPanner() {
    final id = backend.createPanner(_ctxId);
    return WAPannerNode(nodeId: id, contextId: _ctxId);
  }

  /// Create a WaveShaperNode.
  WAWaveShaperNode createWaveShaper() {
    final id = backend.createWaveShaper(_ctxId);
    return WAWaveShaperNode(nodeId: id, contextId: _ctxId);
  }

  /// Create a ConstantSourceNode.
  WAConstantSourceNode createConstantSource() {
    final id = backend.createConstantSource(_ctxId);
    return WAConstantSourceNode(nodeId: id, contextId: _ctxId);
  }

  /// Create a ConvolverNode.
  WAConvolverNode createConvolver() {
    final id = backend.createConvolver(_ctxId);
    return WAConvolverNode(nodeId: id, contextId: _ctxId);
  }

  /// Create an IIRFilterNode.
  WAIIRFilterNode createIIRFilter(
      Float64List feedforward, Float64List feedback) {
    final id = backend.createIIRFilter(_ctxId, feedforward, feedback);
    return WAIIRFilterNode(
      nodeId: id,
      contextId: _ctxId,
      feedforward: feedforward,
      feedback: feedback,
    );
  }

  /// Creates a [WAPeriodicWave] instance.
  WAPeriodicWave createPeriodicWave(Float32List real, Float32List imag,
      {bool disableNormalization = false}) {
    return WAPeriodicWave(
        real: real, imag: imag, disableNormalization: disableNormalization);
  }

  /// Creates a [WAChannelSplitterNode].
  WAChannelSplitterNode createChannelSplitter([int numberOfOutputs = 6]) {
    final id = backend.createChannelSplitter(_ctxId, numberOfOutputs);
    return WAChannelSplitterNode(
        nodeId: id, contextId: _ctxId, numberOfOutputs: numberOfOutputs);
  }

  /// Create a channel merger node.
  WAChannelMergerNode createChannelMerger([int numberOfInputs = 6]) {
    final id = backend.createChannelMerger(_ctxId, numberOfInputs);
    return WAChannelMergerNode(
        nodeId: id, contextId: _ctxId, numberOfInputs: numberOfInputs);
  }

  /// Creates a [WAMediaStreamSourceNode] from the given stream.
  /// In this implementation, the stream usually represents the default microphone.
  WAMediaStreamSourceNode createMediaStreamSource([dynamic stream]) {
    final nodeId = backend.createMediaStreamSource(_ctxId, stream);
    return WAMediaStreamSourceNode(
      nodeId: nodeId,
      contextId: _ctxId,
      mediaStream: backend.mediaStreamSourceGetStream(nodeId),
    );
  }

  /// Creates a microphone source node.
  /// On Web, this triggers the permission prompt and gets the stream.
  /// On Native, this opens the default input device.
  Future<WAMediaStreamSourceNode> createMicrophoneSource() async {
    final stream = await backend.getWebMicrophoneStream();
    return createMediaStreamSource(stream);
  }

  /// Creates a [WAMediaStreamDestNode].
  WAMediaStreamDestNode createMediaStreamDestination() {
    final nodeId = backend.createMediaStreamDestination(_ctxId);
    return WAMediaStreamDestNode(
      nodeId: nodeId,
      contextId: _ctxId,
      stream: backend.mediaStreamDestinationGetStream(nodeId),
    );
  }

  /// Creates a MediaElementAudioSourceNode from a media element (web).
  WAMediaElementSourceNode createMediaElementSource(dynamic mediaElement) {
    final nodeId = backend.createMediaElementSource(_ctxId, mediaElement);
    return WAMediaElementSourceNode(
      nodeId: nodeId,
      contextId: _ctxId,
      mediaElement: mediaElement,
    );
  }

  /// Creates a MediaStreamTrackAudioSourceNode from a media stream track.
  WAMediaStreamTrackSourceNode createMediaStreamTrackSource(
      dynamic mediaStreamTrack) {
    final nodeId =
        backend.createMediaStreamTrackSource(_ctxId, mediaStreamTrack);
    return WAMediaStreamTrackSourceNode(
      nodeId: nodeId,
      contextId: _ctxId,
      mediaStreamTrack: mediaStreamTrack,
    );
  }

  /// Creates a deprecated ScriptProcessorNode shim.
  @Deprecated('ScriptProcessorNode is deprecated. Use createWorkletNode().')
  WAScriptProcessorNode createScriptProcessor(
      [int bufferSize = 0,
      int numberOfInputChannels = 2,
      int numberOfOutputChannels = 2]) {
    final nodeId = backend.createScriptProcessor(
      _ctxId,
      bufferSize,
      numberOfInputChannels,
      numberOfOutputChannels,
    );
    return WAScriptProcessorNode(
      nodeId: nodeId,
      contextId: _ctxId,
      bufferSize: bufferSize,
      numberOfInputChannels: numberOfInputChannels,
      numberOfOutputChannels: numberOfOutputChannels,
    );
  }

  /// Create an AudioWorkletNode.
  WAWorkletNode createWorkletNode(String processorName,
      {Map<String, double> parameterDefaults = const {}}) {
    final hasLocalProcessor = _worklet.hasProcessor(processorName);
    final localModuleDefined =
        WAWorkletModules.resolve(processorName) != null && !hasLocalProcessor;
    if (localModuleDefined) {
      throw StateError('Module for "$processorName" is defined but not loaded. '
          'Call audioWorklet.addModule(...) before createWorkletNode().');
    }
    if (!hasLocalProcessor && !backend.workletSupportsExternalProcessors()) {
      throw StateError(
          'Processor "$processorName" is not available on this backend. '
          'Import/define a Dart worklet module and call audioWorklet.addModule(...) first.');
    }
    final nodeId = backend.createWorkletNode(_ctxId, processorName, 2, 2,
        useProxyProcessor: hasLocalProcessor);
    return WAWorkletNode(
      nodeId: nodeId,
      contextId: _ctxId,
      processorName: processorName,
      worklet: _worklet,
      parameterDefaults: parameterDefaults,
    );
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

  /// Creates a specialized Machine Voice (Optimized batch creation).
  /// Returns nodes in this fixed order:
  /// `Oscillator`, `Filter`, `Gain`, `Panner`, `Delay`, `DelayFb`, `DelayWet`.
  /// This is an optimization to avoid main thread blocking during voice creation.
  List<WANode> createMachineVoice() {
    final ids = backend.createMachineVoice(_ctxId);
    // 0: Osc, 1: Filter, 2: Gain, 3: Panner, 4: Delay, 5: DelayFb, 6: DelayWet
    return [
      WAOscillatorNode(nodeId: ids[0], contextId: _ctxId),
      WABiquadFilterNode(nodeId: ids[1], contextId: _ctxId),
      WAGainNode(nodeId: ids[2], contextId: _ctxId),
      WAStereoPannerNode(nodeId: ids[3], contextId: _ctxId),
      WADelayNode(
          nodeId: ids[4], contextId: _ctxId, maxDelayTime: 5.0), // Safe max
      WAGainNode(nodeId: ids[5], contextId: _ctxId),
      WAGainNode(nodeId: ids[6], contextId: _ctxId),
    ];
  }

  /// Asynchronously creates a specialized Machine Voice on a worker isolate.
  ///
  /// Returns nodes in this fixed order:
  /// `Oscillator`, `Filter`, `Gain`, `Panner`, `Delay`, `DelayFb`, `DelayWet`.
  @Deprecated(
      'Use createMachineVoice(). This async variant will be removed in a future release.')
  Future<List<WANode>> createMachineVoiceAsync() async {
    return createMachineVoice();
  }
}
