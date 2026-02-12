// ignore_for_file: public_member_api_docs
/// JUCE FFI Backend — native platform implementation.
///
/// Loads the compiled wajuce shared library and resolves C-API symbols
/// at runtime via dart:ffi lazy lookups.
library;

import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../audio_buffer.dart';

// ---------------------------------------------------------------------------
// Native library loading
// ---------------------------------------------------------------------------

final ffi.DynamicLibrary _lib = () {
  if (Platform.isMacOS || Platform.isIOS) {
    return ffi.DynamicLibrary.open('wajuce.framework/wajuce');
  } else if (Platform.isAndroid || Platform.isLinux) {
    return ffi.DynamicLibrary.open('libwajuce.so');
  } else if (Platform.isWindows) {
    return ffi.DynamicLibrary.open('wajuce.dll');
  }
  throw UnsupportedError('Platform not supported');
}();

// ---------------------------------------------------------------------------
// FFI typedefs
// ---------------------------------------------------------------------------

// Context
typedef _CtxCreateN = ffi.Int32 Function(
    ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32);
typedef _CtxCreateD = int Function(int, int, int, int);

typedef _CtxVoidN = ffi.Void Function(ffi.Int32);
typedef _CtxVoidD = void Function(int);

typedef _CtxDoubleN = ffi.Double Function(ffi.Int32);
typedef _CtxDoubleD = double Function(int);

typedef _CtxIntN = ffi.Int32 Function(ffi.Int32);
typedef _CtxIntD = int Function(int);

// Node factory
typedef _CreateNodeN = ffi.Int32 Function(ffi.Int32);
typedef _CreateNodeD = int Function(int);
typedef _CreateDelayN = ffi.Int32 Function(ffi.Int32, ffi.Float);
typedef _CreateDelayD = int Function(int, double);
typedef _CreateSplitterN = ffi.Int32 Function(ffi.Int32, ffi.Int32);
typedef _CreateSplitterD = int Function(int, int);

// Graph
typedef _ConnectN = ffi.Void Function(
    ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32);
typedef _ConnectD = void Function(int, int, int, int, int);
typedef _DisconnectN = ffi.Void Function(ffi.Int32, ffi.Int32, ffi.Int32);
typedef _DisconnectD = void Function(int, int, int);
typedef _DisconnectAllN = ffi.Void Function(ffi.Int32, ffi.Int32);
typedef _DisconnectAllD = void Function(int, int);

typedef _RemoveNodeN = ffi.Void Function(ffi.Int32, ffi.Int32);
typedef _RemoveNodeD = void Function(int, int);

// Params
typedef _ParamSetN = ffi.Void Function(
    ffi.Int32, ffi.Pointer<ffi.Char>, ffi.Float);
typedef _ParamSetD = void Function(int, ffi.Pointer<ffi.Char>, double);
typedef _ParamSetAtTimeN = ffi.Void Function(
    ffi.Int32, ffi.Pointer<ffi.Char>, ffi.Float, ffi.Double);
typedef _ParamSetAtTimeD = void Function(
    int, ffi.Pointer<ffi.Char>, double, double);
typedef _ParamRampN = ffi.Void Function(
    ffi.Int32, ffi.Pointer<ffi.Char>, ffi.Float, ffi.Double);
typedef _ParamRampD = void Function(
    int, ffi.Pointer<ffi.Char>, double, double);
typedef _ParamSetTargetN = ffi.Void Function(
    ffi.Int32, ffi.Pointer<ffi.Char>, ffi.Float, ffi.Double, ffi.Float);
typedef _ParamSetTargetD = void Function(
    int, ffi.Pointer<ffi.Char>, double, double, double);
typedef _ParamCancelN = ffi.Void Function(
    ffi.Int32, ffi.Pointer<ffi.Char>, ffi.Double);
typedef _ParamCancelD = void Function(int, ffi.Pointer<ffi.Char>, double);

// Osc
typedef _OscSetTypeN = ffi.Void Function(ffi.Int32, ffi.Int32);
typedef _OscSetTypeD = void Function(int, int);
typedef _OscStartN = ffi.Void Function(ffi.Int32, ffi.Double);
typedef _OscStartD = void Function(int, double);
typedef _OscSetPeriodicWaveN = ffi.Void Function(
    ffi.Int32, ffi.Pointer<ffi.Float>, ffi.Pointer<ffi.Float>, ffi.Int32);
typedef _OscSetPeriodicWaveD = void Function(
    int, ffi.Pointer<ffi.Float>, ffi.Pointer<ffi.Float>, int);

// Filter
typedef _FilterSetTypeN = ffi.Void Function(ffi.Int32, ffi.Int32);
typedef _FilterSetTypeD = void Function(int, int);

// BufferSource
typedef _BufSrcSetBufN = ffi.Void Function(
    ffi.Int32, ffi.Pointer<ffi.Float>, ffi.Int32, ffi.Int32, ffi.Int32);
typedef _BufSrcSetBufD = void Function(
    int, ffi.Pointer<ffi.Float>, int, int, int);
typedef _BufSrcStartN = ffi.Void Function(ffi.Int32, ffi.Double);
typedef _BufSrcStartD = void Function(int, double);
typedef _BufSrcStopN = ffi.Void Function(ffi.Int32, ffi.Double);
typedef _BufSrcStopD = void Function(int, double);
typedef _BufSrcSetLoopN = ffi.Void Function(ffi.Int32, ffi.Int32);
typedef _BufSrcSetLoopD = void Function(int, int);

// Analyser
typedef _AnalyserSetFftN = ffi.Void Function(ffi.Int32, ffi.Int32);
typedef _AnalyserSetFftD = void Function(int, int);
typedef _AnalyserGetByteN = ffi.Void Function(
    ffi.Int32, ffi.Pointer<ffi.Uint8>, ffi.Int32);
typedef _AnalyserGetByteD = void Function(
    int, ffi.Pointer<ffi.Uint8>, int);
typedef _AnalyserGetFloatN = ffi.Void Function(
    ffi.Int32, ffi.Pointer<ffi.Float>, ffi.Int32);
typedef _AnalyserGetFloatD = void Function(
    int, ffi.Pointer<ffi.Float>, int);

// WaveShaper
typedef _WaveShaperSetCurveN = ffi.Void Function(
    ffi.Int32, ffi.Pointer<ffi.Float>, ffi.Int32);
typedef _WaveShaperSetCurveD = void Function(
    int, ffi.Pointer<ffi.Float>, int);
typedef _WaveShaperSetOversampleN = ffi.Void Function(ffi.Int32, ffi.Int32);
typedef _WaveShaperSetOversampleD = void Function(int, int);

// MIDI
typedef _MidiGetPortCountN = ffi.Int32 Function(ffi.Int32);
typedef _MidiGetPortCountD = int Function(int);
typedef _MidiGetPortNameN = ffi.Void Function(
    ffi.Int32, ffi.Int32, ffi.Pointer<ffi.Char>, ffi.Int32);
typedef _MidiGetPortNameD = void Function(
    int, int, ffi.Pointer<ffi.Char>, int);
typedef _MidiPortOpenN = ffi.Void Function(ffi.Int32, ffi.Int32);
typedef _MidiPortOpenD = void Function(int, int);
typedef _MidiOutputSendN = ffi.Void Function(
    ffi.Int32, ffi.Pointer<ffi.Uint8>, ffi.Int32, ffi.Double);
typedef _MidiOutputSendD = void Function(
    int, ffi.Pointer<ffi.Uint8>, int, double);

// Worklet Bridge
typedef _CreateWorkletBridgeN = ffi.Int32 Function(
    ffi.Int32, ffi.Int32, ffi.Int32);
typedef _CreateWorkletBridgeD = int Function(int, int, int);

typedef _WorkletGetBufN = ffi.Pointer<ffi.Float> Function(
    ffi.Int32, ffi.Int32, ffi.Int32);
typedef _WorkletGetBufD = ffi.Pointer<ffi.Float> Function(int, int, int);

typedef _WorkletGetPosN = ffi.Pointer<ffi.Int32> Function(
    ffi.Int32, ffi.Int32, ffi.Int32);
typedef _WorkletGetPosD = ffi.Pointer<ffi.Int32> Function(int, int, int);

typedef _WorkletGetCapN = ffi.Int32 Function(ffi.Int32);
typedef _WorkletGetCapD = int Function(int);

typedef _CreateMachineVoiceN = ffi.Void Function(
    ffi.Int32, ffi.Pointer<ffi.Int32>);
typedef _CreateMachineVoiceD = void Function(int, ffi.Pointer<ffi.Int32>);

// ---------------------------------------------------------------------------
// Lazy FFI lookups
// ---------------------------------------------------------------------------

final _contextCreate =
    _lib.lookupFunction<_CtxCreateN, _CtxCreateD>('wajuce_context_create');
final _contextDestroy =
    _lib.lookupFunction<_CtxVoidN, _CtxVoidD>('wajuce_context_destroy');
final _contextGetTime =
    _lib.lookupFunction<_CtxDoubleN, _CtxDoubleD>('wajuce_context_get_time');
final _contextGetSampleRate = _lib
    .lookupFunction<_CtxDoubleN, _CtxDoubleD>('wajuce_context_get_sample_rate');
final _contextGetState =
    _lib.lookupFunction<_CtxIntN, _CtxIntD>('wajuce_context_get_state');
final _contextResume =
    _lib.lookupFunction<_CtxVoidN, _CtxVoidD>('wajuce_context_resume');
final _contextSuspend =
    _lib.lookupFunction<_CtxVoidN, _CtxVoidD>('wajuce_context_suspend');
final _contextClose =
    _lib.lookupFunction<_CtxVoidN, _CtxVoidD>('wajuce_context_close');
final _contextGetDestinationId = _lib
    .lookupFunction<_CtxIntN, _CtxIntD>('wajuce_context_get_destination_id');

// Node factory
final _createGain =
    _lib.lookupFunction<_CreateNodeN, _CreateNodeD>('wajuce_create_gain');
final _createOscillator = _lib
    .lookupFunction<_CreateNodeN, _CreateNodeD>('wajuce_create_oscillator');
final _createBiquadFilter = _lib
    .lookupFunction<_CreateNodeN, _CreateNodeD>('wajuce_create_biquad_filter');
final _createCompressor = _lib
    .lookupFunction<_CreateNodeN, _CreateNodeD>('wajuce_create_compressor');
final _createDelay =
    _lib.lookupFunction<_CreateDelayN, _CreateDelayD>('wajuce_create_delay');
final _createBufferSource = _lib
    .lookupFunction<_CreateNodeN, _CreateNodeD>('wajuce_create_buffer_source');
final _createAnalyser =
    _lib.lookupFunction<_CreateNodeN, _CreateNodeD>('wajuce_create_analyser');
final _createStereoPanner = _lib
    .lookupFunction<_CreateNodeN, _CreateNodeD>('wajuce_create_stereo_panner');
final _createWaveShaper = _lib
    .lookupFunction<_CreateNodeN, _CreateNodeD>('wajuce_create_wave_shaper');
final _createMediaStreamSource = _lib.lookupFunction<_CreateNodeN,
    _CreateNodeD>('wajuce_create_media_stream_source');
final _createMediaStreamDestination = _lib.lookupFunction<_CreateNodeN,
    _CreateNodeD>('wajuce_create_media_stream_destination');
final _createChannelSplitter = _lib.lookupFunction<_CreateSplitterN,
    _CreateSplitterD>('wajuce_create_channel_splitter');
final _createChannelMerger = _lib.lookupFunction<_CreateSplitterN,
    _CreateSplitterD>('wajuce_create_channel_merger');
final _createMachineVoice = _lib.lookupFunction<_CreateMachineVoiceN,
    _CreateMachineVoiceD>('wajuce_create_machine_voice');

typedef _DecodeAudioDataN = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8> encodedData,
  ffi.Int32 len,
  ffi.Pointer<ffi.Float> outData,
  ffi.Pointer<ffi.Int32> outFrames,
  ffi.Pointer<ffi.Int32> outChannels,
  ffi.Pointer<ffi.Int32> outSr,
);
typedef _DecodeAudioDataD = int Function(
  ffi.Pointer<ffi.Uint8> encodedData,
  int len,
  ffi.Pointer<ffi.Float> outData,
  ffi.Pointer<ffi.Int32> outFrames,
  ffi.Pointer<ffi.Int32> outChannels,
  ffi.Pointer<ffi.Int32> outSr,
);
final _decodeAudioData =
    _lib.lookupFunction<_DecodeAudioDataN, _DecodeAudioDataD>(
        'wajuce_decode_audio_data');

// Graph
final _connect =
    _lib.lookupFunction<_ConnectN, _ConnectD>('wajuce_connect');
final _disconnect =
    _lib.lookupFunction<_DisconnectN, _DisconnectD>('wajuce_disconnect');
final _disconnectAll =
    _lib.lookupFunction<_DisconnectAllN, _DisconnectAllD>(
        'wajuce_disconnect_all');
final _removeNode =
    _lib.lookupFunction<_RemoveNodeN, _RemoveNodeD>('wajuce_context_remove_node');

// Params
final _paramSet =
    _lib.lookupFunction<_ParamSetN, _ParamSetD>('wajuce_param_set');
final _paramSetAtTime = _lib
    .lookupFunction<_ParamSetAtTimeN, _ParamSetAtTimeD>(
        'wajuce_param_set_at_time');
final _paramLinearRamp = _lib
    .lookupFunction<_ParamRampN, _ParamRampD>('wajuce_param_linear_ramp');
final _paramExpRamp =
    _lib.lookupFunction<_ParamRampN, _ParamRampD>('wajuce_param_exp_ramp');
final _paramSetTarget = _lib.lookupFunction<_ParamSetTargetN, _ParamSetTargetD>(
    'wajuce_param_set_target');
final _paramCancel =
    _lib.lookupFunction<_ParamCancelN, _ParamCancelD>('wajuce_param_cancel');

// Osc
final _oscSetType =
    _lib.lookupFunction<_OscSetTypeN, _OscSetTypeD>('wajuce_osc_set_type');
final _oscStart =
    _lib.lookupFunction<_OscStartN, _OscStartD>('wajuce_osc_start');
final _oscStop =
    _lib.lookupFunction<_OscStartN, _OscStartD>('wajuce_osc_stop');
final _oscSetPeriodicWave = _lib.lookupFunction<_OscSetPeriodicWaveN,
    _OscSetPeriodicWaveD>('wajuce_osc_set_periodic_wave');

// Filter
final _filterSetType = _lib.lookupFunction<_FilterSetTypeN, _FilterSetTypeD>(
    'wajuce_filter_set_type');

// BufferSource
final _bufSrcSetBuffer =
    _lib.lookupFunction<_BufSrcSetBufN, _BufSrcSetBufD>(
        'wajuce_buffer_source_set_buffer');
final _bufSrcStart =
    _lib.lookupFunction<_BufSrcStartN, _BufSrcStartD>(
        'wajuce_buffer_source_start');
final _bufSrcStop =
    _lib.lookupFunction<_BufSrcStopN, _BufSrcStopD>(
        'wajuce_buffer_source_stop');
final _bufSrcSetLoop =
    _lib.lookupFunction<_BufSrcSetLoopN, _BufSrcSetLoopD>(
        'wajuce_buffer_source_set_loop');

// Analyser
final _analyserSetFft =
    _lib.lookupFunction<_AnalyserSetFftN, _AnalyserSetFftD>(
        'wajuce_analyser_set_fft_size');
final _analyserGetByteFreq =
    _lib.lookupFunction<_AnalyserGetByteN, _AnalyserGetByteD>(
        'wajuce_analyser_get_byte_freq');
final _analyserGetByteTime =
    _lib.lookupFunction<_AnalyserGetByteN, _AnalyserGetByteD>(
        'wajuce_analyser_get_byte_time');
final _analyserGetFloatFreq =
    _lib.lookupFunction<_AnalyserGetFloatN, _AnalyserGetFloatD>(
        'wajuce_analyser_get_float_freq');
final _analyserGetFloatTime =
    _lib.lookupFunction<_AnalyserGetFloatN, _AnalyserGetFloatD>(
        'wajuce_analyser_get_float_time');

// WaveShaper
final _waveShaperSetCurve =
    _lib.lookupFunction<_WaveShaperSetCurveN, _WaveShaperSetCurveD>(
        'wajuce_wave_shaper_set_curve');
final _waveShaperSetOversample =
    _lib.lookupFunction<_WaveShaperSetOversampleN, _WaveShaperSetOversampleD>(
        'wajuce_wave_shaper_set_oversample');

// MIDI
final _midiGetPortCount =
    _lib.lookupFunction<_MidiGetPortCountN, _MidiGetPortCountD>(
        'wajuce_midi_get_port_count');
final _midiGetPortName =
    _lib.lookupFunction<_MidiGetPortNameN, _MidiGetPortNameD>(
        'wajuce_midi_get_port_name');
final _midiPortOpen =
    _lib.lookupFunction<_MidiPortOpenN, _MidiPortOpenD>(
        'wajuce_midi_port_open');
final _midiPortClose =
    _lib.lookupFunction<_MidiPortOpenN, _MidiPortOpenD>(
        'wajuce_midi_port_close');
final _midiOutputSend =
    _lib.lookupFunction<_MidiOutputSendN, _MidiOutputSendD>(
        'wajuce_midi_output_send');

// Worklet Bridge
final _createWorkletBridge =
    _lib.lookupFunction<_CreateWorkletBridgeN, _CreateWorkletBridgeD>(
        'wajuce_create_worklet_bridge');
final _workletGetBufferPtr =
    _lib.lookupFunction<_WorkletGetBufN, _WorkletGetBufD>(
        'wajuce_worklet_get_buffer_ptr');
final _workletGetReadPosPtr =
    _lib.lookupFunction<_WorkletGetPosN, _WorkletGetPosD>(
        'wajuce_worklet_get_read_pos_ptr');
final _workletGetWritePosPtr =
    _lib.lookupFunction<_WorkletGetPosN, _WorkletGetPosD>(
        'wajuce_worklet_get_write_pos_ptr');
final _workletGetCapacity =
    _lib.lookupFunction<_WorkletGetCapN, _WorkletGetCapD>(
        'wajuce_worklet_get_capacity');

typedef _MidiCallbackN = ffi.Void Function(ffi.Int32 portIndex,
    ffi.Pointer<ffi.Uint8> data, ffi.Int32 len, ffi.Double timestamp);
typedef _SetMidiCallbackN = ffi.Void Function(
    ffi.Pointer<ffi.NativeFunction<_MidiCallbackN>>);
typedef _SetMidiCallbackD = void Function(
    ffi.Pointer<ffi.NativeFunction<_MidiCallbackN>>);
final _setMidiCallback =
    _lib.lookupFunction<_SetMidiCallbackN, _SetMidiCallbackD>(
        'wajuce_midi_set_callback');
final _midiDispose =
    _lib.lookupFunction<ffi.Void Function(), void Function()>(
        'wajuce_midi_dispose');

// ---------------------------------------------------------------------------
// Helper: Dart String → native C string (caller must free)
// ---------------------------------------------------------------------------

ffi.Pointer<ffi.Char> _toCString(String s) {
  final units = Uint8List.fromList([...s.codeUnits, 0]);
  final ptr = calloc<ffi.Uint8>(units.length);
  ptr.asTypedList(units.length).setAll(0, units);
  return ptr.cast<ffi.Char>();
}

void _freeCString(ffi.Pointer<ffi.Char> ptr) {
  calloc.free(ptr);
}

// ---------------------------------------------------------------------------
// Backend API — Context
// ---------------------------------------------------------------------------

int contextCreate(int sampleRate, int bufferSize,
    {int inputChannels = 2, int outputChannels = 2}) {
  // print('[wajuce] Dart: contextCreate sr=$sampleRate, bs=$bufferSize, inCh=$inputChannels, outCh=$outputChannels');
  final id = _contextCreate(sampleRate, bufferSize, inputChannels, outputChannels);
  // print('[wajuce] Dart: contextCreated, native id=$id');
  return id;
}

void contextDestroy(int ctxId) => _contextDestroy(ctxId);
double contextGetTime(int ctxId) => _contextGetTime(ctxId);
double contextGetSampleRate(int ctxId) => _contextGetSampleRate(ctxId);
int contextGetState(int ctxId) => _contextGetState(ctxId);
void contextResume(int ctxId) => _contextResume(ctxId);
void contextSuspend(int ctxId) => _contextSuspend(ctxId);
void contextClose(int ctxId) => _contextClose(ctxId);
int contextGetDestinationId(int ctxId) => _contextGetDestinationId(ctxId);

int createChannelSplitter(int id, int outputs) =>
    _createChannelSplitter(id, outputs);
int createChannelMerger(int id, int inputs) =>
    _createChannelMerger(id, inputs);

// ---------------------------------------------------------------------------
// Backend API — Node Factory
// ---------------------------------------------------------------------------

int createGain(int ctxId) => _createGain(ctxId);
int createOscillator(int ctxId) => _createOscillator(ctxId);
int createBiquadFilter(int ctxId) => _createBiquadFilter(ctxId);
int createCompressor(int ctxId) => _createCompressor(ctxId);
int createDelay(int ctxId, double maxDelay) => _createDelay(ctxId, maxDelay);
int createBufferSource(int ctxId) => _createBufferSource(ctxId);
int createAnalyser(int ctxId) => _createAnalyser(ctxId);
int createStereoPanner(int ctxId) => _createStereoPanner(ctxId);
int createWaveShaper(int ctxId) => _createWaveShaper(ctxId);
int createMediaStreamSource(int ctxId) => _createMediaStreamSource(ctxId);
int createMediaStreamDestination(int ctxId) =>
    _createMediaStreamDestination(ctxId);

List<int> createMachineVoice(int ctxId) {
  final ptr = calloc<ffi.Int32>(7);
  _createMachineVoice(ctxId, ptr);
  final result = List<int>.from(ptr.asTypedList(7));
  calloc.free(ptr);
  return result;
}

// ---------------------------------------------------------------------------
// Backend API — Graph
// ---------------------------------------------------------------------------

void connect(int ctxId, int srcId, int dstId, int output, int input) {
  _connect(ctxId, srcId, dstId, output, input);
}

void disconnect(int ctxId, int srcId, int dstId) {
  _disconnect(ctxId, srcId, dstId);
}

void disconnectAll(int ctxId, int srcId) {
  _disconnectAll(ctxId, srcId);
}

void removeNode(int ctxId, int nodeId) {
  _removeNode(ctxId, nodeId);
}

// ---------------------------------------------------------------------------
// Backend API — AudioParam
// ---------------------------------------------------------------------------

void paramSet(int nodeId, String paramName, double value) {
  final p = _toCString(paramName);
  _paramSet(nodeId, p, value);
  _freeCString(p);
}

void paramSetAtTime(int nodeId, String paramName, double value, double time) {
  final p = _toCString(paramName);
  _paramSetAtTime(nodeId, p, value, time);
  _freeCString(p);
}

void paramLinearRamp(int nodeId, String paramName, double value, double endTime) {
  final p = _toCString(paramName);
  _paramLinearRamp(nodeId, p, value, endTime);
  _freeCString(p);
}

void paramExpRamp(int nodeId, String paramName, double value, double endTime) {
  final p = _toCString(paramName);
  _paramExpRamp(nodeId, p, value, endTime);
  _freeCString(p);
}

void paramSetTarget(
    int nodeId, String paramName, double target, double startTime, double tc) {
  final p = _toCString(paramName);
  _paramSetTarget(nodeId, p, target, startTime, tc);
  _freeCString(p);
}

void paramCancel(int nodeId, String paramName, double cancelTime) {
  final p = _toCString(paramName);
  _paramCancel(nodeId, p, cancelTime);
  _freeCString(p);
}

// ---------------------------------------------------------------------------
// Backend API — Oscillator
// ---------------------------------------------------------------------------

void oscSetType(int nodeId, int type) => _oscSetType(nodeId, type);
void oscStart(int nodeId, double when) => _oscStart(nodeId, when);
void oscStop(int nodeId, double when) => _oscStop(nodeId, when);

// PeriodicWave support
void oscSetPeriodicWave(int nodeId, Float32List real, Float32List imag, int len) {
  using((arena) {
    final pReal = arena<ffi.Float>(len);
    final pImag = arena<ffi.Float>(len);
    for (int i = 0; i < len; i++) {
      pReal[i] = real[i];
      pImag[i] = imag[i];
    }
    _oscSetPeriodicWave(nodeId, pReal, pImag, len);
  });
}

// ---------------------------------------------------------------------------
// Backend API — Filter
// ---------------------------------------------------------------------------

void filterSetType(int nodeId, int type) => _filterSetType(nodeId, type);

// ---------------------------------------------------------------------------
// Backend API — BufferSource
// ---------------------------------------------------------------------------

void bufferSourceSetBuffer(int nodeId, WABuffer buffer) {
  final channels = buffer.numberOfChannels;
  final frames = buffer.length;
  // Pack channel data: [ch0_frame0..ch0_frameN, ch1_frame0..ch1_frameN, ...]
  final totalSamples = frames * channels;
  final nativeData = calloc<ffi.Float>(totalSamples);
  for (int ch = 0; ch < channels; ch++) {
    final channelData = buffer.getChannelData(ch);
    for (int i = 0; i < frames; i++) {
      nativeData[ch * frames + i] = channelData[i];
    }
  }
  _bufSrcSetBuffer(nodeId, nativeData, frames, channels, buffer.sampleRate.toInt());
  calloc.free(nativeData);
}

void bufferSourceStart(int nodeId, [double when = 0]) {
  _bufSrcStart(nodeId, when);
}

void bufferSourceStop(int nodeId, [double when = 0]) {
  _bufSrcStop(nodeId, when);
}

void bufferSourceSetLoop(int nodeId, bool loop) {
  _bufSrcSetLoop(nodeId, loop ? 1 : 0);
}

// ---------------------------------------------------------------------------
// Backend API — Analyser
// ---------------------------------------------------------------------------

void analyserSetFftSize(int nodeId, int size) {
  _analyserSetFft(nodeId, size);
}

Uint8List analyserGetByteFrequencyData(int nodeId, int len) {
  final ptr = calloc<ffi.Uint8>(len);
  _analyserGetByteFreq(nodeId, ptr, len);
  final result = Uint8List.fromList(ptr.asTypedList(len));
  calloc.free(ptr);
  return result;
}

Uint8List analyserGetByteTimeDomainData(int nodeId, int len) {
  final ptr = calloc<ffi.Uint8>(len);
  _analyserGetByteTime(nodeId, ptr, len);
  final result = Uint8List.fromList(ptr.asTypedList(len));
  calloc.free(ptr);
  return result;
}

Float32List analyserGetFloatFrequencyData(int nodeId, int len) {
  final ptr = calloc<ffi.Float>(len);
  _analyserGetFloatFreq(nodeId, ptr, len);
  final result = Float32List.fromList(ptr.asTypedList(len));
  calloc.free(ptr);
  return result;
}

Float32List analyserGetFloatTimeDomainData(int nodeId, int len) {
  final ptr = calloc<ffi.Float>(len);
  _analyserGetFloatTime(nodeId, ptr, len);
  final result = Float32List.fromList(ptr.asTypedList(len));
  calloc.free(ptr);
  return result;
}

// ---------------------------------------------------------------------------
// Backend API — WaveShaper
// ---------------------------------------------------------------------------

void waveShaperSetCurve(int nodeId, Float32List curve) {
  final ptr = calloc<ffi.Float>(curve.length);
  ptr.asTypedList(curve.length).setAll(0, curve);
  _waveShaperSetCurve(nodeId, ptr, curve.length);
  calloc.free(ptr);
}

void waveShaperSetOversample(int nodeId, int type) {
  _waveShaperSetOversample(nodeId, type);
}

// ---------------------------------------------------------------------------
// Backend API — Buffer (Dart-side only, no native call needed)
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
  final encodedDataPtr = calloc<ffi.Uint8>(data.length);
  encodedDataPtr.asTypedList(data.length).setAll(0, data);

  final framesPtr = calloc<ffi.Int32>();
  final channelsPtr = calloc<ffi.Int32>();
  final srPtr = calloc<ffi.Int32>();

  // First pass: get dimensions
  final res = _decodeAudioData(encodedDataPtr, data.length, ffi.Pointer.fromAddress(0),
      framesPtr, channelsPtr, srPtr);

  if (res != 0) {
    calloc.free(encodedDataPtr);
    calloc.free(framesPtr);
    calloc.free(channelsPtr);
    calloc.free(srPtr);
    throw Exception('Failed to decode audio data');
  }

  final frames = framesPtr.value;
  final channels = channelsPtr.value;
  final sampleRate = srPtr.value;

  // Second pass: get data
  final outDataPtr = calloc<ffi.Float>(frames * channels);
  _decodeAudioData(encodedDataPtr, data.length, outDataPtr, framesPtr,
      channelsPtr, srPtr);

  final buffer = WABuffer(
    numberOfChannels: channels,
    length: frames,
    sampleRate: sampleRate.toDouble(),
  );

  final flatData = outDataPtr.asTypedList(frames * channels);
  for (int ch = 0; ch < channels; ch++) {
    final channelData = Float32List.fromList(
        flatData.sublist(ch * frames, (ch + 1) * frames));
    buffer.copyToChannel(channelData, ch);
  }

  calloc.free(encodedDataPtr);
  calloc.free(framesPtr);
  calloc.free(channelsPtr);
  calloc.free(srPtr);
  calloc.free(outDataPtr);

  return buffer;
}

// ---------------------------------------------------------------------------
// Backend API — WorkletBridge (Phase 8)
// ---------------------------------------------------------------------------

int createWorkletNode(int ctxId, int numInputs, int numOutputs) {
  return _createWorkletBridge(ctxId, numInputs, numOutputs);
}

ffi.Pointer<ffi.Float> workletGetBufferPtr(
        int bridgeId, int direction, int channel) =>
    _workletGetBufferPtr(bridgeId, direction, channel);

ffi.Pointer<ffi.Int32> workletGetReadPosPtr(
        int bridgeId, int direction, int channel) =>
    _workletGetReadPosPtr(bridgeId, direction, channel);

ffi.Pointer<ffi.Int32> workletGetWritePosPtr(
        int bridgeId, int direction, int channel) =>
    _workletGetWritePosPtr(bridgeId, direction, channel);

int workletGetCapacity(int bridgeId) => _workletGetCapacity(bridgeId);

// ---------------------------------------------------------------------------
// Backend API — MIDI
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

Future<bool> midiRequestAccess({bool sysex = false}) async {
  // On native JUCE, MIDI is always available
  return true;
}

Future<MidiDeviceInfoBackend> midiGetDevices() async {
  final inputCount = _midiGetPortCount(0);
  final outputCount = _midiGetPortCount(1);

  final inputNames = <String>[];
  final outputNames = <String>[];
  final nameBuf = calloc<ffi.Char>(256);

  for (int i = 0; i < inputCount; i++) {
    _midiGetPortName(0, i, nameBuf, 256);
    inputNames.add(nameBuf.cast<Utf8>().toDartString());
  }

  for (int i = 0; i < outputCount; i++) {
    _midiGetPortName(1, i, nameBuf, 256);
    outputNames.add(nameBuf.cast<Utf8>().toDartString());
  }

  calloc.free(nameBuf);

  return MidiDeviceInfoBackend(
    inputCount: inputCount,
    outputCount: outputCount,
    inputNames: inputNames,
    outputNames: outputNames,
    inputManufacturers: List.filled(inputCount, ''),
    outputManufacturers: List.filled(outputCount, ''),
  );
}

void Function(int portIndex, Uint8List data, double timestamp)?
    onMidiMessageReceived;

ffi.NativeCallable<_MidiCallbackN>? _midiCallable;

void _initMidi() {
  if (_midiCallable != null) return;
  _midiCallable =
      ffi.NativeCallable<_MidiCallbackN>.listener(_nativeMidiCallback);
  _setMidiCallback(_midiCallable!.nativeFunction);
}

void _nativeMidiCallback(
    int portIndex, ffi.Pointer<ffi.Uint8> data, int len, double timestamp) {
  final bytes = Uint8List.fromList(data.asTypedList(len));
  onMidiMessageReceived?.call(portIndex, bytes, timestamp);
}

void midiInputOpen(int portIndex) {
  _initMidi();
  _midiPortOpen(0, portIndex);
}

void midiInputClose(int portIndex) => _midiPortClose(0, portIndex);
void midiOutputOpen(int portIndex) => _midiPortOpen(1, portIndex);
void midiOutputClose(int portIndex) => _midiPortClose(1, portIndex);

void midiOutputSend(int portIndex, Uint8List data, double timestamp) {
  final ptr = calloc<ffi.Uint8>(data.length);
  ptr.asTypedList(data.length).setAll(0, data);
  _midiOutputSend(portIndex, ptr, data.length, timestamp);
  calloc.free(ptr);
}

void midiDispose() {
  _midiDispose();
  _midiCallable?.close();
  _midiCallable = null;
}
