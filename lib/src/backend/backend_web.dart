// ignore_for_file: public_member_api_docs
/// Web Audio Backend — browser implementation via dart:js_interop.
///
/// Passes through all calls to the browser's native Web Audio API.
/// Uses integer IDs mapped to JS objects for consistency with
/// the native backend's ID-based approach.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import '../audio_buffer.dart';

// ---------------------------------------------------------------------------
// JS Interop extension types for Web Audio API
// ---------------------------------------------------------------------------

@JS('AudioContext')
extension type JSAudioContext._(JSObject _) implements JSObject {
  external JSAudioContext([JSObject? options]);
  external JSNumber get currentTime;
  external JSNumber get sampleRate;
  external JSString get state;
  external JSPromise resume();
  external JSPromise suspend();
  external JSPromise close();
  external JSAudioDestinationNode get destination;
  external JSGainNode createGain();
  external JSOscillatorNode createOscillator();
  external JSBiquadFilterNode createBiquadFilter();
  external JSDynamicsCompressorNode createDynamicsCompressor();
  external JSDelayNode createDelay([JSNumber? maxDelayTime]);
  external JSAudioBufferSourceNode createBufferSource();
  external JSAnalyserNode createAnalyser();
  external JSStereoPannerNode createStereoPanner();
  external JSWaveShaperNode createWaveShaper();
  external JSAudioBuffer createBuffer(
      JSNumber numberOfChannels, JSNumber length, JSNumber sampleRate);
  external JSPromise decodeAudioData(JSArrayBuffer audioData);
}

@JS('AudioDestinationNode')
extension type JSAudioDestinationNode._(JSObject _) implements JSObject {
  external void connect(JSObject destination);
  external void disconnect([JSObject? destination]);
}

@JS('GainNode')
extension type JSGainNode._(JSObject _) implements JSObject {
  external JSAudioParam get gain;
  external void connect(JSObject destination);
  external void disconnect([JSObject? destination]);
}

@JS('OscillatorNode')
extension type JSOscillatorNode._(JSObject _) implements JSObject {
  external JSAudioParam get frequency;
  external JSAudioParam get detune;
  external set type(JSString value);
  external void start([JSNumber? when]);
  external void stop([JSNumber? when]);
  external void connect(JSObject destination);
  external void disconnect([JSObject? destination]);
}

@JS('BiquadFilterNode')
extension type JSBiquadFilterNode._(JSObject _) implements JSObject {
  external JSAudioParam get frequency;
  external JSAudioParam get Q;
  external JSAudioParam get gain;
  external JSAudioParam get detune;
  external set type(JSString value);
  external void connect(JSObject destination);
  external void disconnect([JSObject? destination]);
}

@JS('DynamicsCompressorNode')
extension type JSDynamicsCompressorNode._(JSObject _) implements JSObject {
  external JSAudioParam get threshold;
  external JSAudioParam get knee;
  external JSAudioParam get ratio;
  external JSAudioParam get attack;
  external JSAudioParam get release;
  external void connect(JSObject destination);
  external void disconnect([JSObject? destination]);
}

@JS('DelayNode')
extension type JSDelayNode._(JSObject _) implements JSObject {
  external JSAudioParam get delayTime;
  external void connect(JSObject destination);
  external void disconnect([JSObject? destination]);
}

@JS('AudioBufferSourceNode')
extension type JSAudioBufferSourceNode._(JSObject _) implements JSObject {
  external JSAudioParam get playbackRate;
  external JSAudioParam get detune;
  external set buffer(JSAudioBuffer? buf);
  external set loop(JSBoolean value);
  external void start([JSNumber? when]);
  external void stop([JSNumber? when]);
  external void connect(JSObject destination);
  external void disconnect([JSObject? destination]);
}

@JS('AnalyserNode')
extension type JSAnalyserNode._(JSObject _) implements JSObject {
  external set fftSize(JSNumber value);
  external JSNumber get frequencyBinCount;
  external void getByteFrequencyData(JSUint8Array array);
  external void getByteTimeDomainData(JSUint8Array array);
  external void getFloatFrequencyData(JSFloat32Array array);
  external void getFloatTimeDomainData(JSFloat32Array array);
  external void connect(JSObject destination);
  external void disconnect([JSObject? destination]);
}

@JS('StereoPannerNode')
extension type JSStereoPannerNode._(JSObject _) implements JSObject {
  external JSAudioParam get pan;
  external void connect(JSObject destination);
  external void disconnect([JSObject? destination]);
}

@JS('WaveShaperNode')
extension type JSWaveShaperNode._(JSObject _) implements JSObject {
  external set curve(JSFloat32Array? value);
  external set oversample(JSString value);
  external void connect(JSObject destination);
  external void disconnect([JSObject? destination]);
}

@JS('AudioParam')
extension type JSAudioParam._(JSObject _) implements JSObject {
  external set value(JSNumber v);
  external JSNumber get value;
  external JSAudioParam setValueAtTime(JSNumber value, JSNumber startTime);
  external JSAudioParam linearRampToValueAtTime(
      JSNumber value, JSNumber endTime);
  external JSAudioParam exponentialRampToValueAtTime(
      JSNumber value, JSNumber endTime);
  external JSAudioParam setTargetAtTime(
      JSNumber target, JSNumber startTime, JSNumber timeConstant);
  external JSAudioParam cancelScheduledValues(JSNumber startTime);
}

@JS('AudioBuffer')
extension type JSAudioBuffer._(JSObject _) implements JSObject {
  external JSNumber get numberOfChannels;
  external JSNumber get length;
  external JSNumber get sampleRate;
  external JSFloat32Array getChannelData(JSNumber channel);
  external void copyToChannel(JSFloat32Array source, JSNumber channelNumber);
}

// ---------------------------------------------------------------------------
// ID → JSObject registry
// ---------------------------------------------------------------------------

int _nextId = 1;
final Map<int, JSObject> _nodes = {};
final Map<int, JSAudioContext> _contexts = {};

/// Resolve the AudioParam for a given node by paramName
JSAudioParam? _getParam(int nodeId, String paramName) {
  final node = _nodes[nodeId];
  if (node == null) return null;
  // Use getProperty for dynamic access
  try {
    return node.getProperty(paramName.toJS) as JSAudioParam;
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Backend API — Context
// ---------------------------------------------------------------------------

int contextCreate(int sampleRate, int bufferSize) {
  final ctx = JSAudioContext();
  final id = _nextId++;
  _contexts[id] = ctx;
  // Destination node is always ID 0
  _nodes[0] = ctx.destination as JSObject;
  return id;
}

void contextDestroy(int ctxId) {
  _contexts.remove(ctxId);
}

double contextGetTime(int ctxId) {
  final ctx = _contexts[ctxId];
  return ctx?.currentTime.toDartDouble ?? 0.0;
}

double contextGetSampleRate(int ctxId) {
  final ctx = _contexts[ctxId];
  return ctx?.sampleRate.toDartDouble ?? 44100.0;
}

int contextGetState(int ctxId) {
  final ctx = _contexts[ctxId];
  if (ctx == null) return 2;
  final s = ctx.state.toDart;
  switch (s) {
    case 'suspended':
      return 0;
    case 'running':
      return 1;
    case 'closed':
      return 2;
    default:
      return 0;
  }
}

void contextResume(int ctxId) {
  _contexts[ctxId]?.resume();
}

void contextSuspend(int ctxId) {
  _contexts[ctxId]?.suspend();
}

void contextClose(int ctxId) {
  _contexts[ctxId]?.close();
}

int contextGetDestinationId(int ctxId) => 0;

// ---------------------------------------------------------------------------
// Backend API — Node Factory
// ---------------------------------------------------------------------------

int createGain(int ctxId) {
  final ctx = _contexts[ctxId]!;
  final node = ctx.createGain();
  final id = _nextId++;
  _nodes[id] = node as JSObject;
  return id;
}

int createOscillator(int ctxId) {
  final ctx = _contexts[ctxId]!;
  final node = ctx.createOscillator();
  final id = _nextId++;
  _nodes[id] = node as JSObject;
  return id;
}

int createBiquadFilter(int ctxId) {
  final ctx = _contexts[ctxId]!;
  final node = ctx.createBiquadFilter();
  final id = _nextId++;
  _nodes[id] = node as JSObject;
  return id;
}

int createCompressor(int ctxId) {
  final ctx = _contexts[ctxId]!;
  final node = ctx.createDynamicsCompressor();
  final id = _nextId++;
  _nodes[id] = node as JSObject;
  return id;
}

int createDelay(int ctxId, double maxDelay) {
  final ctx = _contexts[ctxId]!;
  final node = ctx.createDelay(maxDelay.toJS);
  final id = _nextId++;
  _nodes[id] = node as JSObject;
  return id;
}

int createBufferSource(int ctxId) {
  final ctx = _contexts[ctxId]!;
  final node = ctx.createBufferSource();
  final id = _nextId++;
  _nodes[id] = node as JSObject;
  return id;
}

int createAnalyser(int ctxId) {
  final ctx = _contexts[ctxId]!;
  final node = ctx.createAnalyser();
  final id = _nextId++;
  _nodes[id] = node as JSObject;
  return id;
}

int createStereoPanner(int ctxId) {
  final ctx = _contexts[ctxId]!;
  final node = ctx.createStereoPanner();
  final id = _nextId++;
  _nodes[id] = node as JSObject;
  return id;
}

int createWaveShaper(int ctxId) {
  final ctx = _contexts[ctxId]!;
  final node = ctx.createWaveShaper();
  final id = _nextId++;
  _nodes[id] = node as JSObject;
  return id;
}

// ---------------------------------------------------------------------------
// Backend API — Graph
// ---------------------------------------------------------------------------

void connect(int ctxId, int srcId, int dstId, int output, int input) {
  final src = _nodes[srcId];
  final dst = _nodes[dstId];
  if (src == null || dst == null) return;
  // Use callMethod for connect
  src.callMethod('connect'.toJS, dst);
}

void disconnect(int ctxId, int srcId, int dstId) {
  final src = _nodes[srcId];
  final dst = _nodes[dstId];
  if (src == null) return;
  if (dst != null) {
    src.callMethod('disconnect'.toJS, dst);
  } else {
    src.callMethod('disconnect'.toJS);
  }
}

void disconnectAll(int ctxId, int srcId) {
  // handled by GC usually, but could call disconnect()
}

void removeNode(int ctxId, int nodeId) {
  // Web Audio doesn't have explicit node disposal, just disconnect and let GC handle it.
  disconnectAll(ctxId, nodeId);
}

// ---------------------------------------------------------------------------
// Backend API — AudioParam
// ---------------------------------------------------------------------------

void paramSet(int nodeId, String paramName, double value) {
  final param = _getParam(nodeId, paramName);
  param?.value = value.toJS;
}

void paramSetAtTime(int nodeId, String paramName, double value, double time) {
  final param = _getParam(nodeId, paramName);
  param?.setValueAtTime(value.toJS, time.toJS);
}

void paramLinearRamp(
    int nodeId, String paramName, double value, double endTime) {
  final param = _getParam(nodeId, paramName);
  param?.linearRampToValueAtTime(value.toJS, endTime.toJS);
}

void paramExpRamp(int nodeId, String paramName, double value, double endTime) {
  final param = _getParam(nodeId, paramName);
  param?.exponentialRampToValueAtTime(value.toJS, endTime.toJS);
}

void paramSetTarget(
    int nodeId, String paramName, double target, double startTime, double tc) {
  final param = _getParam(nodeId, paramName);
  param?.setTargetAtTime(target.toJS, startTime.toJS, tc.toJS);
}

void paramCancel(int nodeId, String paramName, double cancelTime) {
  final param = _getParam(nodeId, paramName);
  param?.cancelScheduledValues(cancelTime.toJS);
}

// ---------------------------------------------------------------------------
// Backend API — Oscillator
// ---------------------------------------------------------------------------

const _oscTypes = ['sine', 'square', 'sawtooth', 'triangle', 'custom'];

void oscSetType(int nodeId, int type) {
  final node = _nodes[nodeId] as JSOscillatorNode?;
  if (node != null && type < _oscTypes.length) {
    node.type = _oscTypes[type].toJS;
  }
}

void oscStart(int nodeId, double when) {
  final node = _nodes[nodeId] as JSOscillatorNode?;
  node?.start(when.toJS);
}

void oscStop(int nodeId, double when) {
  final node = _nodes[nodeId] as JSOscillatorNode?;
  node?.stop(when.toJS);
}

// ---------------------------------------------------------------------------
// Backend API — Filter
// ---------------------------------------------------------------------------

const _filterTypes = [
  'lowpass',
  'highpass',
  'bandpass',
  'lowshelf',
  'highshelf',
  'peaking',
  'notch',
  'allpass',
];

void filterSetType(int nodeId, int type) {
  final node = _nodes[nodeId] as JSBiquadFilterNode?;
  if (node != null && type < _filterTypes.length) {
    node.type = _filterTypes[type].toJS;
  }
}

// ---------------------------------------------------------------------------
// Backend API — BufferSource
// ---------------------------------------------------------------------------

void bufferSourceSetBuffer(int nodeId, WABuffer buffer) {
  final node = _nodes[nodeId] as JSAudioBufferSourceNode?;
  if (node == null) return;

  // Find the AudioContext (first one)
  final ctx = _contexts.values.first;
  final jsBuf = ctx.createBuffer(
    buffer.numberOfChannels.toJS,
    buffer.length.toJS,
    buffer.sampleRate.toJS,
  );
  for (int ch = 0; ch < buffer.numberOfChannels; ch++) {
    final data = buffer.getChannelData(ch);
    jsBuf.copyToChannel(data.toJS, ch.toJS);
  }
  node.buffer = jsBuf;
}

void bufferSourceStart(int nodeId, [double when = 0]) {
  final node = _nodes[nodeId] as JSAudioBufferSourceNode?;
  node?.start(when.toJS);
}

void bufferSourceStop(int nodeId, [double when = 0]) {
  final node = _nodes[nodeId] as JSAudioBufferSourceNode?;
  node?.stop(when.toJS);
}

void bufferSourceSetLoop(int nodeId, bool loop) {
  final node = _nodes[nodeId] as JSAudioBufferSourceNode?;
  node?.loop = loop.toJS;
}

// ---------------------------------------------------------------------------
// Backend API — Analyser
// ---------------------------------------------------------------------------

void analyserSetFftSize(int nodeId, int size) {
  final node = _nodes[nodeId] as JSAnalyserNode?;
  node?.fftSize = size.toJS;
}

Uint8List analyserGetByteFrequencyData(int nodeId, int len) {
  final node = _nodes[nodeId] as JSAnalyserNode?;
  if (node == null) return Uint8List(len);
  final arr = Uint8List(len);
  node.getByteFrequencyData(arr.toJS);
  return arr;
}

Uint8List analyserGetByteTimeDomainData(int nodeId, int len) {
  final node = _nodes[nodeId] as JSAnalyserNode?;
  if (node == null) return Uint8List(len);
  final arr = Uint8List(len);
  node.getByteTimeDomainData(arr.toJS);
  return arr;
}

Float32List analyserGetFloatFrequencyData(int nodeId, int len) {
  final node = _nodes[nodeId] as JSAnalyserNode?;
  if (node == null) return Float32List(len);
  final arr = Float32List(len);
  node.getFloatFrequencyData(arr.toJS);
  return arr;
}

Float32List analyserGetFloatTimeDomainData(int nodeId, int len) {
  final node = _nodes[nodeId] as JSAnalyserNode?;
  if (node == null) return Float32List(len);
  final arr = Float32List(len);
  node.getFloatTimeDomainData(arr.toJS);
  return arr;
}

// ---------------------------------------------------------------------------
// Backend API — WaveShaper
// ---------------------------------------------------------------------------

void waveShaperSetCurve(int nodeId, Float32List curve) {
  final node = _nodes[nodeId] as JSWaveShaperNode?;
  node?.curve = curve.toJS;
}

const _oversampleTypes = ['none', '2x', '4x'];

void waveShaperSetOversample(int nodeId, int type) {
  final node = _nodes[nodeId] as JSWaveShaperNode?;
  if (node != null && type < _oversampleTypes.length) {
    node.oversample = _oversampleTypes[type].toJS;
  }
}

// ---------------------------------------------------------------------------
// Backend API — Buffer
// ---------------------------------------------------------------------------

int _nextBufferId = 1;
final Map<int, WABuffer> _bufferStore = {};

int createBuffer(int numberOfChannels, int length, int sampleRate) {
  final id = _nextBufferId++;
  _bufferStore[id] = WABuffer(
    numberOfChannels: numberOfChannels,
    length: length,
    sampleRate: sampleRate,
  );
  return id;
}

WABuffer? getBuffer(int bufferId) => _bufferStore[bufferId];

Future<WABuffer> decodeAudioData(int ctxId, Uint8List data) async {
  final ctx = _contexts[ctxId]!;
  final arrayBuffer = data.buffer.toJS;
  final jsResult = await ctx.decodeAudioData(arrayBuffer).toDart;
  final jsBuf = jsResult as JSAudioBuffer;

  final buffer = WABuffer(
    numberOfChannels: jsBuf.numberOfChannels.toDartInt,
    length: jsBuf.length.toDartInt,
    sampleRate: jsBuf.sampleRate.toDartInt,
  );

  for (int ch = 0; ch < buffer.numberOfChannels; ch++) {
    final channelData = jsBuf.getChannelData(ch.toJS);
    buffer.copyToChannel(channelData.toDart, ch);
  }

  return buffer;
}

// ---------------------------------------------------------------------------
// Backend API — WorkletBridge (Phase 8)
// ---------------------------------------------------------------------------

int createWorkletNode(int ctxId, int numInputs, int numOutputs) => -1;

// ---------------------------------------------------------------------------
// Backend API — MIDI (Web MIDI API)
// ---------------------------------------------------------------------------

/// MIDI device info container for backend.
class MidiDeviceInfoBackend {
  final int inputCount;
  final int outputCount;
  final List<String> inputNames;
  final List<String> outputNames;
  final List<String> inputManufacturers;
  final List<String> outputManufacturers;

  MidiDeviceInfoBackend({
    required this.inputCount,
    required this.outputCount,
    required this.inputNames,
    required this.outputNames,
    required this.inputManufacturers,
    required this.outputManufacturers,
  });
}

JSObject? _midiAccess;

Future<bool> midiRequestAccess({bool sysex = false}) async {
  try {
    final navigator = globalContext.getProperty('navigator'.toJS) as JSObject;
    final options = JSObject();
    options.setProperty('sysex'.toJS, sysex.toJS);
    final promise = navigator.callMethod('requestMIDIAccess'.toJS, options)
        as JSPromise;
    final access = await promise.toDart;
    _midiAccess = access as JSObject;
    return true;
  } catch (e) {
    return false;
  }
}

Future<MidiDeviceInfoBackend> midiGetDevices() async {
  if (_midiAccess == null) {
    return MidiDeviceInfoBackend(
      inputCount: 0,
      outputCount: 0,
      inputNames: [],
      outputNames: [],
      inputManufacturers: [],
      outputManufacturers: [],
    );
  }

  final inputNames = <String>[];
  final outputNames = <String>[];
  final inputManufacturers = <String>[];
  final outputManufacturers = <String>[];

  // Iterate MIDI inputs
  final inputs = _midiAccess!.getProperty('inputs'.toJS) as JSObject;
  final inputIterator = inputs.callMethod('values'.toJS) as JSObject;
  while (true) {
    final result = inputIterator.callMethod('next'.toJS) as JSObject;
    final done = (result.getProperty('done'.toJS) as JSBoolean).toDart;
    if (done) break;
    final port = result.getProperty('value'.toJS) as JSObject;
    inputNames
        .add((port.getProperty('name'.toJS) as JSString?)?.toDart ?? 'Unknown');
    inputManufacturers.add(
        (port.getProperty('manufacturer'.toJS) as JSString?)?.toDart ?? '');
  }

  // Iterate MIDI outputs
  final outputs = _midiAccess!.getProperty('outputs'.toJS) as JSObject;
  final outputIterator = outputs.callMethod('values'.toJS) as JSObject;
  while (true) {
    final result = outputIterator.callMethod('next'.toJS) as JSObject;
    final done = (result.getProperty('done'.toJS) as JSBoolean).toDart;
    if (done) break;
    final port = result.getProperty('value'.toJS) as JSObject;
    outputNames
        .add((port.getProperty('name'.toJS) as JSString?)?.toDart ?? 'Unknown');
    outputManufacturers.add(
        (port.getProperty('manufacturer'.toJS) as JSString?)?.toDart ?? '');
  }

  return MidiDeviceInfoBackend(
    inputCount: inputNames.length,
    outputCount: outputNames.length,
    inputNames: inputNames,
    outputNames: outputNames,
    inputManufacturers: inputManufacturers,
    outputManufacturers: outputManufacturers,
  );
}

final Map<int, JSObject> _midiInputPorts = {};
final Map<int, JSObject> _midiOutputPorts = {};

JSObject? _getMidiPort(bool isInput, int index) {
  if (_midiAccess == null) return null;
  final mapName = isInput ? 'inputs' : 'outputs';
  final map = _midiAccess!.getProperty(mapName.toJS) as JSObject;
  final iterator = map.callMethod('values'.toJS) as JSObject;
  int i = 0;
  while (true) {
    final result = iterator.callMethod('next'.toJS) as JSObject;
    final done = (result.getProperty('done'.toJS) as JSBoolean).toDart;
    if (done) return null;
    if (i == index) {
      return result.getProperty('value'.toJS) as JSObject;
    }
    i++;
  }
}

void midiInputOpen(int portIndex) {
  final port = _getMidiPort(true, portIndex);
  if (port != null) {
    port.callMethod('open'.toJS);
    _midiInputPorts[portIndex] = port;
  }
}

void midiInputClose(int portIndex) {
  final port = _midiInputPorts.remove(portIndex);
  port?.callMethod('close'.toJS);
}

void midiOutputOpen(int portIndex) {
  final port = _getMidiPort(false, portIndex);
  if (port != null) {
    port.callMethod('open'.toJS);
    _midiOutputPorts[portIndex] = port;
  }
}

void midiOutputClose(int portIndex) {
  final port = _midiOutputPorts.remove(portIndex);
  port?.callMethod('close'.toJS);
}

void midiOutputSend(int portIndex, Uint8List data, double timestamp) {
  final port = _midiOutputPorts[portIndex];
  if (port == null) return;
  final jsData = data.toJS;
  if (timestamp > 0) {
    port.callMethod('send'.toJS, jsData, timestamp.toJS);
  } else {
    port.callMethod('send'.toJS, jsData);
  }
}

void midiDispose() {
  for (final port in _midiInputPorts.values) {
    port.callMethod('close'.toJS);
  }
  for (final port in _midiOutputPorts.values) {
    port.callMethod('close'.toJS);
  }
  _midiInputPorts.clear();
  _midiOutputPorts.clear();
  _midiAccess = null;
}
