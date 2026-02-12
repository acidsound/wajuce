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
  external JSObject get destination;
  external JSObject createGain();
  external JSObject createOscillator();
  external JSObject createBiquadFilter();
  external JSObject createDynamicsCompressor();
  external JSObject createDelay([JSNumber? maxDelayTime]);
  external JSObject createBufferSource();
  external JSObject createAnalyser();
  external JSObject createStereoPanner();
  external JSObject createWaveShaper();
  external JSObject createChannelSplitter([JSNumber? numberOfOutputs]);
  external JSObject createChannelMerger([JSNumber? numberOfInputs]);
  external JSAudioBuffer createBuffer(
      JSNumber numberOfChannels, JSNumber length, JSNumber sampleRate);
  external JSPeriodicWave createPeriodicWave(
      JSFloat32Array real, JSFloat32Array imag, [JSObject? options]);
  external JSPromise decodeAudioData(JSArrayBuffer audioData);
  external JSObject createMediaStreamSource(JSObject stream);
  external JSObject createScriptProcessor([JSNumber? bufferSize, JSNumber? numberOfInputChannels, JSNumber? numberOfOutputChannels]);
}

@JS('PeriodicWave')
extension type JSPeriodicWave._(JSObject _) implements JSObject {}

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
  try {
    return node.getProperty(paramName.toJS) as JSAudioParam;
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Backend API — Context
// ---------------------------------------------------------------------------

int contextCreate(int sampleRate, int bufferSize,
    {int inputChannels = 2, int outputChannels = 2}) {
  final ctx = JSAudioContext();
  final id = _nextId++;
  _contexts[id] = ctx;
  _nodes[0] = ctx.destination;
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
  final node = _contexts[ctxId]!.createGain();
  final id = _nextId++;
  _nodes[id] = node;
  return id;
}

int createOscillator(int ctxId) {
  final node = _contexts[ctxId]!.createOscillator();
  final id = _nextId++;
  _nodes[id] = node;
  return id;
}

int createBiquadFilter(int ctxId) {
  final node = _contexts[ctxId]!.createBiquadFilter();
  final id = _nextId++;
  _nodes[id] = node;
  return id;
}

int createCompressor(int ctxId) {
  final node = _contexts[ctxId]!.createDynamicsCompressor();
  final id = _nextId++;
  _nodes[id] = node;
  return id;
}

int createDelay(int ctxId, double maxDelay) {
  final node = _contexts[ctxId]!.createDelay(maxDelay.toJS);
  final id = _nextId++;
  _nodes[id] = node;
  return id;
}

int createBufferSource(int ctxId) {
  final node = _contexts[ctxId]!.createBufferSource();
  final id = _nextId++;
  _nodes[id] = node;
  return id;
}

int createAnalyser(int ctxId) {
  final node = _contexts[ctxId]!.createAnalyser();
  final id = _nextId++;
  _nodes[id] = node;
  return id;
}

int createStereoPanner(int ctxId) {
  final node = _contexts[ctxId]!.createStereoPanner();
  final id = _nextId++;
  _nodes[id] = node;
  return id;
}

int createWaveShaper(int ctxId) {
  final node = _contexts[ctxId]!.createWaveShaper();
  final id = _nextId++;
  _nodes[id] = node;
  return id;
}

int createChannelSplitter(int ctxId, int outputs) {
  final node = _contexts[ctxId]!.createChannelSplitter(outputs.toJS);
  final id = _nextId++;
  _nodes[id] = node;
  return id;
}

int createChannelMerger(int ctxId, int inputs) {
  final node = _contexts[ctxId]!.createChannelMerger(inputs.toJS);
  final id = _nextId++;
  _nodes[id] = node;
  return id;
}

int createMediaStreamSource(int ctxId, [dynamic stream]) {
  if (stream == null) {
      throw UnimplementedError('MediaStreamSource on Web needs explicit stream object');
  }
  final node = _contexts[ctxId]!.createMediaStreamSource(stream as JSObject);
  final id = _nextId++;
  _nodes[id] = node;
  return id;
}

int createMediaStreamDestination(int ctxId) {
  final ctx = _contexts[ctxId]!;
  final node = ctx.callMethod('createMediaStreamDestination'.toJS) as JSObject;
  final id = _nextId++;
  _nodes[id] = node;
  return id;
}


// ---------------------------------------------------------------------------
// Worklet & I/O
// ---------------------------------------------------------------------------

/// The minimal JS AudioWorkletProcessor code to drive the Dart side.
/// This acts as a reliable clock source from the Audio Thread.
const _kWorkletModuleSource = r'''
class WajuceProxyProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this._frameCounter = 0;
  }

  process(inputs, outputs, parameters) {
    // Notify Dart main thread every 128 frames (1 block)
    // We strictly use the Audio Thread clock here.
    this.port.postMessage({
      'type': 'process',
      'frameCount': 128
    });
    
    // Pass audio through if inputs connected (basic passthrough for now)
    // Real DSP happens in the Dart callback triggered by the message, 
    // but actual audio manipulation on Web would require WASM for performance.
    // For the Sequencer Clock, this 'tick' is what matters.
    const input = inputs[0];
    const output = outputs[0];
    if (input && output && input.length > 0) {
      for (let channel = 0; channel < output.length; channel++) {
         if (input[channel]) {
            output[channel].set(input[channel]);
         }
      }
    }
    
    return true;
  }
}
registerProcessor('wajuce-proxy-processor', WajuceProxyProcessor);
''';

bool _moduleLoaded = false;

Future<void> _ensureWorkletModuleLoaded(int ctxId) async {
  if (_moduleLoaded) return;
  final ctx = _contexts[ctxId];
  if (ctx == null) return;

  // Create a Blob from the source string
  final blob = JSBlob(
    [_kWorkletModuleSource.toJS].toJS,
    JSBlobPropertyBag(type: 'application/javascript'.toJS),
  );
  
  final worklet = ctx.audioWorklet;
  if (worklet != null) {
      final url = createObjectURL(blob);
      await worklet.addModule(url).toDart;
      _moduleLoaded = true;
  }
}

// Callback interface for Dart side
void Function(int nodeId)? onWebProcessQuantum;

int createWorkletNode(int ctxId, int numInputs, int numOutputs) {
  // We cannot block here to wait for addModule (async), 
  // so we assume it's called during initialization or we handle the promise externally.
  // However, for strict compatibility, we should ensure the module is loaded.
  // In this synchronous C-API style method, we'll create the node. 
  // Warning: addModule MUST be called before this.
  
  final ctx = _contexts[ctxId]!;
  final node = JSAudioWorkletNode(ctx, 'wajuce-proxy-processor'.toJS);
  
  final id = _nextId++;
  _nodes[id] = node;

  // Listen to the 'tick' from the AudioWorkletProcessor
  node.port.setProperty('onmessage'.toJS, (JSObject event) {
      // Treat this as the processing tick
      onWebProcessQuantum?.call(id);
  }.toJS);

  return id;
}

/// Helper for initializing the worklet module from Dart
Future<void> webInitializeWorklet(int ctxId) async {
  await _ensureWorkletModuleLoaded(ctxId);
}

int workletGetCapacity(int bridgeId) => 0; // Not used on Web
int workletGetBufferPtr(int bridgeId, int type, int channel) => 0; 
int workletGetReadPosPtr(int bridgeId, int type, int channel) => 0;
int workletGetWritePosPtr(int bridgeId, int type, int channel) => 0;

List<int> createMachineVoice(int ctxId) {
  // Fallback for Web: create individual nodes (Dart side handles connection)
  // We return a list of NEGATIVE IDs or standard IDs to indicate
  // that the caller should manually route them.
  // Actually, the caller (backend wrapper or main) handles the fallback exception.
  throw UnimplementedError('createMachineVoice native optimization not supported on Web');
}

// ---------------------------------------------------------------------------
// JS Interop definitions for Worklet
// ---------------------------------------------------------------------------

@JS()
external JSObject get URL;

@JS('URL.createObjectURL')
// ignore: non_constant_identifier_names
external JSString createObjectURL(JSBlob blob);

@JS('Blob')
extension type JSBlob._(JSObject _) implements JSObject {
  external JSBlob(JSArray blobParts, [JSBlobPropertyBag options]);
}

@JS()
@anonymous
extension type JSBlobPropertyBag._(JSObject _) implements JSObject {
  external factory JSBlobPropertyBag({JSString type});
}

@JS('AudioWorklet')
extension type JSAudioWorklet._(JSObject _) implements JSObject {
  external JSPromise addModule(JSString moduleURL);
}

@JS('AudioWorkletNode')
extension type JSAudioWorkletNode._(JSObject _) implements JSObject {
  external JSAudioWorkletNode(JSAudioContext context, JSString name);
  external JSAudioParam get parameters;
  external JSObject get port; // MessagePort
}

extension JSAudioContextExtension on JSAudioContext {
  external JSAudioWorklet? get audioWorklet;
}

// ---------------------------------------------------------------------------
// MediaDevices Interop
// ---------------------------------------------------------------------------

@JS('navigator.mediaDevices')
external JSMediaDevices? get mediaDevices;

@JS('MediaDevices')
extension type JSMediaDevices._(JSObject _) implements JSObject {
  external JSPromise getUserMedia([JSObject? constraints]);
}

Future<JSObject?> getWebMicrophoneStream() async {
  if (mediaDevices == null) return null;
  try {
     // Request audio only
     final constraints = JSObject();
     constraints.setProperty('audio'.toJS, true.toJS);
     constraints.setProperty('video'.toJS, false.toJS);
     
     final promise = mediaDevices!.getUserMedia(constraints);
     final stream = await promise.toDart;
     return stream as JSObject;
  } catch (e) {
    // print('Error getting user media: $e');
    return null;
  }
}

// ---------------------------------------------------------------------------
// Backend API — Graph
// ---------------------------------------------------------------------------

void connect(int ctxId, int srcId, int dstId, int output, int input) {
  final src = _nodes[srcId];
  final dst = _nodes[dstId];
  if (src == null || dst == null) return;
  src.callMethod('connect'.toJS, dst, output.toJS, input.toJS);
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
  _nodes[srcId]?.callMethod('disconnect'.toJS);
}

void removeNode(int ctxId, int nodeId) {
  disconnectAll(ctxId, nodeId);
  _nodes.remove(nodeId);
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
  final node = _nodes[nodeId];
  if (node != null && type < _oscTypes.length) {
    node.setProperty('type'.toJS, _oscTypes[type].toJS);
  }
}

void oscStart(int nodeId, double when) {
  _nodes[nodeId]?.callMethod('start'.toJS, when.toJS);
}

void oscStop(int nodeId, double when) {
  _nodes[nodeId]?.callMethod('stop'.toJS, when.toJS);
}

void oscSetPeriodicWave(int nodeId, Float32List real, Float32List imag, int len) {
  final node = _nodes[nodeId];
  if (node == null) return;
  // Use first context as default
  final ctx = _contexts.values.first;
  final wave = ctx.createPeriodicWave(real.toJS, imag.toJS);
  node.callMethod('setPeriodicWave'.toJS, wave);
}

// ---------------------------------------------------------------------------
// Backend API — Filter
// ---------------------------------------------------------------------------

const _filterTypes = [
  'lowpass', 'highpass', 'bandpass', 'lowshelf', 'highshelf', 'peaking', 'notch', 'allpass',
];

void filterSetType(int nodeId, int type) {
  final node = _nodes[nodeId];
  if (node != null && type < _filterTypes.length) {
    node.setProperty('type'.toJS, _filterTypes[type].toJS);
  }
}

// ---------------------------------------------------------------------------
// Backend API — BufferSource
// ---------------------------------------------------------------------------

void bufferSourceSetBuffer(int nodeId, WABuffer buffer) {
  final node = _nodes[nodeId];
  if (node == null) return;

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
  node.setProperty('buffer'.toJS, jsBuf);
}

void bufferSourceStart(int nodeId, [double when = 0]) {
  _nodes[nodeId]?.callMethod('start'.toJS, when.toJS);
}

void bufferSourceStop(int nodeId, [double when = 0]) {
  _nodes[nodeId]?.callMethod('stop'.toJS, when.toJS);
}

void bufferSourceSetLoop(int nodeId, bool loop) {
  _nodes[nodeId]?.setProperty('loop'.toJS, loop.toJS);
}

// ---------------------------------------------------------------------------
// Backend API — Analyser
// ---------------------------------------------------------------------------

void analyserSetFftSize(int nodeId, int size) {
  _nodes[nodeId]?.setProperty('fftSize'.toJS, size.toJS);
}

Uint8List analyserGetByteFrequencyData(int nodeId, int len) {
  final node = _nodes[nodeId];
  if (node == null) return Uint8List(len);
  final arr = Uint8List(len);
  node.callMethod('getByteFrequencyData'.toJS, arr.toJS);
  return arr;
}

Uint8List analyserGetByteTimeDomainData(int nodeId, int len) {
  final node = _nodes[nodeId];
  if (node == null) return Uint8List(len);
  final arr = Uint8List(len);
  node.callMethod('getByteTimeDomainData'.toJS, arr.toJS);
  return arr;
}

Float32List analyserGetFloatFrequencyData(int nodeId, int len) {
  final node = _nodes[nodeId];
  if (node == null) return Float32List(len);
  final arr = Float32List(len);
  node.callMethod('getFloatFrequencyData'.toJS, arr.toJS);
  return arr;
}

Float32List analyserGetFloatTimeDomainData(int nodeId, int len) {
  final node = _nodes[nodeId];
  if (node == null) return Float32List(len);
  final arr = Float32List(len);
  node.callMethod('getFloatTimeDomainData'.toJS, arr.toJS);
  return arr;
}

// ---------------------------------------------------------------------------
// Backend API — WaveShaper
// ---------------------------------------------------------------------------

void waveShaperSetCurve(int nodeId, Float32List curve) {
  _nodes[nodeId]?.setProperty('curve'.toJS, curve.toJS);
}

const _oversampleTypes = ['none', '2x', '4x'];

void waveShaperSetOversample(int nodeId, int type) {
  final node = _nodes[nodeId];
  if (node != null && type < _oversampleTypes.length) {
    node.setProperty('oversample'.toJS, _oversampleTypes[type].toJS);
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
// Backend API — MIDI (Web MIDI API)
// ---------------------------------------------------------------------------

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

void Function(int portIndex, Uint8List data, double timestamp)? onMidiMessageReceived;

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
      inputCount: 0, outputCount: 0,
      inputNames: [], outputNames: [],
      inputManufacturers: [], outputManufacturers: [],
    );
  }

  final inputNames = <String>[];
  final outputNames = <String>[];
  final inputManufacturers = <String>[];
  final outputManufacturers = <String>[];

  final inputs = _midiAccess!.getProperty('inputs'.toJS) as JSObject;
  final inputIterator = inputs.callMethod('values'.toJS) as JSObject;
  while (true) {
    final result = inputIterator.callMethod('next'.toJS) as JSObject;
    if ((result.getProperty('done'.toJS) as JSBoolean).toDart) break;
    final port = result.getProperty('value'.toJS) as JSObject;
    inputNames.add((port.getProperty('name'.toJS) as JSString?)?.toDart ?? 'Unknown');
    inputManufacturers.add((port.getProperty('manufacturer'.toJS) as JSString?)?.toDart ?? '');
  }

  final outputs = _midiAccess!.getProperty('outputs'.toJS) as JSObject;
  final outputIterator = outputs.callMethod('values'.toJS) as JSObject;
  while (true) {
    final result = outputIterator.callMethod('next'.toJS) as JSObject;
    if ((result.getProperty('done'.toJS) as JSBoolean).toDart) break;
    final port = result.getProperty('value'.toJS) as JSObject;
    outputNames.add((port.getProperty('name'.toJS) as JSString?)?.toDart ?? 'Unknown');
    outputManufacturers.add((port.getProperty('manufacturer'.toJS) as JSString?)?.toDart ?? '');
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
  final map = _midiAccess!.getProperty((isInput ? 'inputs' : 'outputs').toJS) as JSObject;
  final iterator = map.callMethod('values'.toJS) as JSObject;
  int i = 0;
  while (true) {
    final result = iterator.callMethod('next'.toJS) as JSObject;
    if ((result.getProperty('done'.toJS) as JSBoolean).toDart) return null;
    if (i == index) return result.getProperty('value'.toJS) as JSObject;
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
  _midiInputPorts.remove(portIndex)?.callMethod('close'.toJS);
}

void midiOutputOpen(int portIndex) {
  final port = _getMidiPort(false, portIndex);
  if (port != null) {
    port.callMethod('open'.toJS);
    _midiOutputPorts[portIndex] = port;
  }
}

void midiOutputClose(int portIndex) {
  _midiOutputPorts.remove(portIndex)?.callMethod('close'.toJS);
}

void midiOutputSend(int portIndex, Uint8List data, double timestamp) {
  final port = _midiOutputPorts[portIndex];
  if (port == null) return;
  if (timestamp > 0) {
    port.callMethod('send'.toJS, data.toJS, timestamp.toJS);
  } else {
    port.callMethod('send'.toJS, data.toJS);
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
