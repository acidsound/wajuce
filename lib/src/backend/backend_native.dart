// ignore_for_file: public_member_api_docs
/// Native FFI backend — native platform implementation.
///
/// Loads the compiled wajuce shared library and resolves C-API symbols
/// at runtime via dart:ffi lazy lookups.
library;

import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:math' as math;
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

typedef _CtxSetPreferredSampleRateN = ffi.Int32 Function(ffi.Int32, ffi.Double);
typedef _CtxSetPreferredSampleRateD = int Function(int, double);
typedef _CtxSetPreferredBitDepthN = ffi.Int32 Function(ffi.Int32, ffi.Int32);
typedef _CtxSetPreferredBitDepthD = int Function(int, int);
typedef _CtxRenderN = ffi.Int32 Function(
    ffi.Int32, ffi.Pointer<ffi.Float>, ffi.Int32, ffi.Int32);
typedef _CtxRenderD = int Function(int, ffi.Pointer<ffi.Float>, int, int);

// Node factory
typedef _CreateNodeN = ffi.Int32 Function(ffi.Int32);
typedef _CreateNodeD = int Function(int);
typedef _CreateDelayN = ffi.Int32 Function(ffi.Int32, ffi.Float);
typedef _CreateDelayD = int Function(int, double);
typedef _CreateSplitterN = ffi.Int32 Function(ffi.Int32, ffi.Int32);
typedef _CreateSplitterD = int Function(int, int);
typedef _CreateIIRFilterN = ffi.Int32 Function(ffi.Int32,
    ffi.Pointer<ffi.Double>, ffi.Int32, ffi.Pointer<ffi.Double>, ffi.Int32);
typedef _CreateIIRFilterD = int Function(
    int, ffi.Pointer<ffi.Double>, int, ffi.Pointer<ffi.Double>, int);

// Graph
typedef _ConnectN = ffi.Void Function(
    ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32);
typedef _ConnectD = void Function(int, int, int, int, int);
typedef _ConnectParamN = ffi.Void Function(
    ffi.Int32, ffi.Int32, ffi.Int32, ffi.Pointer<ffi.Char>, ffi.Int32);
typedef _ConnectParamD = void Function(
    int, int, int, ffi.Pointer<ffi.Char>, int);
typedef _DisconnectN = ffi.Void Function(ffi.Int32, ffi.Int32, ffi.Int32);
typedef _DisconnectD = void Function(int, int, int);
typedef _DisconnectOutputN = ffi.Void Function(ffi.Int32, ffi.Int32, ffi.Int32);
typedef _DisconnectOutputD = void Function(int, int, int);
typedef _DisconnectNodeOutputN = ffi.Void Function(
    ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32);
typedef _DisconnectNodeOutputD = void Function(int, int, int, int);
typedef _DisconnectNodeInputN = ffi.Void Function(
    ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32);
typedef _DisconnectNodeInputD = void Function(int, int, int, int, int);
typedef _DisconnectParamN = ffi.Void Function(
    ffi.Int32, ffi.Int32, ffi.Int32, ffi.Pointer<ffi.Char>, ffi.Int32);
typedef _DisconnectParamD = void Function(
    int, int, int, ffi.Pointer<ffi.Char>, int);
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
typedef _ParamRampD = void Function(int, ffi.Pointer<ffi.Char>, double, double);
typedef _ParamSetTargetN = ffi.Void Function(
    ffi.Int32, ffi.Pointer<ffi.Char>, ffi.Float, ffi.Double, ffi.Float);
typedef _ParamSetTargetD = void Function(
    int, ffi.Pointer<ffi.Char>, double, double, double);
typedef _ParamSetValueCurveN = ffi.Void Function(
    ffi.Int32,
    ffi.Pointer<ffi.Char>,
    ffi.Pointer<ffi.Float>,
    ffi.Int32,
    ffi.Double,
    ffi.Double);
typedef _ParamSetValueCurveD = void Function(
    int, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Float>, int, double, double);
typedef _ParamCancelN = ffi.Void Function(
    ffi.Int32, ffi.Pointer<ffi.Char>, ffi.Double);
typedef _ParamCancelD = void Function(int, ffi.Pointer<ffi.Char>, double);
typedef _ParamGetN = ffi.Float Function(ffi.Int32, ffi.Pointer<ffi.Char>);
typedef _ParamGetD = double Function(int, ffi.Pointer<ffi.Char>);

// Osc
typedef _OscSetTypeN = ffi.Void Function(ffi.Int32, ffi.Int32);
typedef _OscSetTypeD = void Function(int, int);
typedef _OscStartN = ffi.Void Function(ffi.Int32, ffi.Double);
typedef _OscStartD = void Function(int, double);
typedef _OscSetPeriodicWaveN = ffi.Void Function(ffi.Int32,
    ffi.Pointer<ffi.Float>, ffi.Pointer<ffi.Float>, ffi.Int32, ffi.Int32);
typedef _OscSetPeriodicWaveD = void Function(
    int, ffi.Pointer<ffi.Float>, ffi.Pointer<ffi.Float>, int, int);

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
typedef _BufSrcStartAdvancedN = ffi.Void Function(
    ffi.Int32, ffi.Double, ffi.Double, ffi.Double, ffi.Int32);
typedef _BufSrcStartAdvancedD = void Function(int, double, double, double, int);
typedef _BufSrcStopN = ffi.Void Function(ffi.Int32, ffi.Double);
typedef _BufSrcStopD = void Function(int, double);
typedef _BufSrcSetLoopN = ffi.Void Function(ffi.Int32, ffi.Int32);
typedef _BufSrcSetLoopD = void Function(int, int);
typedef _BufSrcSetLoopPointsN = ffi.Void Function(
    ffi.Int32, ffi.Double, ffi.Double);
typedef _BufSrcSetLoopPointsD = void Function(int, double, double);

// Analyser
typedef _AnalyserSetFftN = ffi.Void Function(ffi.Int32, ffi.Int32);
typedef _AnalyserSetFftD = void Function(int, int);
typedef _AnalyserSetDoubleN = ffi.Void Function(ffi.Int32, ffi.Double);
typedef _AnalyserSetDoubleD = void Function(int, double);
typedef _AnalyserGetByteN = ffi.Void Function(
    ffi.Int32, ffi.Pointer<ffi.Uint8>, ffi.Int32);
typedef _AnalyserGetByteD = void Function(int, ffi.Pointer<ffi.Uint8>, int);
typedef _AnalyserGetFloatN = ffi.Void Function(
    ffi.Int32, ffi.Pointer<ffi.Float>, ffi.Int32);
typedef _AnalyserGetFloatD = void Function(int, ffi.Pointer<ffi.Float>, int);
typedef _BiquadGetFrequencyResponseN = ffi.Void Function(
    ffi.Int32,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Int32);
typedef _BiquadGetFrequencyResponseD = void Function(
    int,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    int);
typedef _CompressorGetReductionN = ffi.Float Function(ffi.Int32);
typedef _CompressorGetReductionD = double Function(int);
typedef _PannerSetIntN = ffi.Void Function(ffi.Int32, ffi.Int32);
typedef _PannerSetIntD = void Function(int, int);
typedef _PannerSetDoubleN = ffi.Void Function(ffi.Int32, ffi.Double);
typedef _PannerSetDoubleD = void Function(int, double);

// WaveShaper
typedef _WaveShaperSetCurveN = ffi.Void Function(
    ffi.Int32, ffi.Pointer<ffi.Float>, ffi.Int32);
typedef _WaveShaperSetCurveD = void Function(int, ffi.Pointer<ffi.Float>, int);
typedef _WaveShaperSetOversampleN = ffi.Void Function(ffi.Int32, ffi.Int32);
typedef _WaveShaperSetOversampleD = void Function(int, int);
typedef _ConvolverSetBufferN = ffi.Void Function(ffi.Int32,
    ffi.Pointer<ffi.Float>, ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32);
typedef _ConvolverSetBufferD = void Function(
    int, ffi.Pointer<ffi.Float>, int, int, int, int);
typedef _ConvolverSetNormalizeN = ffi.Void Function(ffi.Int32, ffi.Int32);
typedef _ConvolverSetNormalizeD = void Function(int, int);

// MIDI
typedef _MidiGetPortCountN = ffi.Int32 Function(ffi.Int32);
typedef _MidiGetPortCountD = int Function(int);
typedef _MidiGetPortNameN = ffi.Void Function(
    ffi.Int32, ffi.Int32, ffi.Pointer<ffi.Char>, ffi.Int32);
typedef _MidiGetPortNameD = void Function(int, int, ffi.Pointer<ffi.Char>, int);
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
    ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32);
typedef _WorkletGetBufD = ffi.Pointer<ffi.Float> Function(int, int, int, int);

typedef _WorkletGetPosValueN = ffi.Int32 Function(
    ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32);
typedef _WorkletGetPosValueD = int Function(int, int, int, int);

typedef _WorkletSetPosValueN = ffi.Void Function(
    ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32);
typedef _WorkletSetPosValueD = void Function(int, int, int, int, int);

typedef _WorkletGetChannelCountN = ffi.Int32 Function(ffi.Int32, ffi.Int32);
typedef _WorkletGetChannelCountD = int Function(int, int);

typedef _WorkletGetCapN = ffi.Int32 Function(ffi.Int32, ffi.Int32);
typedef _WorkletGetCapD = int Function(int, int);

typedef _WorkletReleaseBridgeN = ffi.Void Function(ffi.Int32, ffi.Int32);
typedef _WorkletReleaseBridgeD = void Function(int, int);

typedef _CreateMachineVoiceN = ffi.Void Function(
    ffi.Int32, ffi.Pointer<ffi.Int32>);
typedef _CreateMachineVoiceD = void Function(int, ffi.Pointer<ffi.Int32>);
typedef _SetMachineVoiceActiveN = ffi.Void Function(
    ffi.Int32, ffi.Int32, ffi.Int32);
typedef _SetMachineVoiceActiveD = void Function(int, int, int);

// ---------------------------------------------------------------------------
// Lazy FFI lookups
// ---------------------------------------------------------------------------

final _contextCreate =
    _lib.lookupFunction<_CtxCreateN, _CtxCreateD>('wajuce_context_create');
final _contextDestroy =
    _lib.lookupFunction<_CtxVoidN, _CtxVoidD>('wajuce_context_destroy');
final _contextGetTime =
    _lib.lookupFunction<_CtxDoubleN, _CtxDoubleD>('wajuce_context_get_time');
final _contextGetLiveNodeCount = _lib
    .lookupFunction<_CtxIntN, _CtxIntD>('wajuce_context_get_live_node_count');
final _contextGetFeedbackBridgeCount = _lib.lookupFunction<_CtxIntN, _CtxIntD>(
    'wajuce_context_get_feedback_bridge_count');
final _contextGetMachineVoiceGroupCount =
    _lib.lookupFunction<_CtxIntN, _CtxIntD>(
        'wajuce_context_get_machine_voice_group_count');
final _contextGetSampleRate = _lib
    .lookupFunction<_CtxDoubleN, _CtxDoubleD>('wajuce_context_get_sample_rate');
final _contextGetBitDepth =
    _lib.lookupFunction<_CtxIntN, _CtxIntD>('wajuce_context_get_bit_depth');
final _contextSetPreferredSampleRate = _lib.lookupFunction<
    _CtxSetPreferredSampleRateN,
    _CtxSetPreferredSampleRateD>('wajuce_context_set_preferred_sample_rate');
final _contextSetPreferredBitDepth =
    _lib.lookupFunction<_CtxSetPreferredBitDepthN, _CtxSetPreferredBitDepthD>(
        'wajuce_context_set_preferred_bit_depth');
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
final _contextGetListenerId =
    _lib.lookupFunction<_CtxIntN, _CtxIntD>('wajuce_context_get_listener_id');
final _contextRender =
    _lib.lookupFunction<_CtxRenderN, _CtxRenderD>('wajuce_context_render');

// Node factory
final _createGain =
    _lib.lookupFunction<_CreateNodeN, _CreateNodeD>('wajuce_create_gain');
final _createOscillator =
    _lib.lookupFunction<_CreateNodeN, _CreateNodeD>('wajuce_create_oscillator');
final _createBiquadFilter = _lib
    .lookupFunction<_CreateNodeN, _CreateNodeD>('wajuce_create_biquad_filter');
final _createCompressor =
    _lib.lookupFunction<_CreateNodeN, _CreateNodeD>('wajuce_create_compressor');
final _createDelay =
    _lib.lookupFunction<_CreateDelayN, _CreateDelayD>('wajuce_create_delay');
final _createBufferSource = _lib
    .lookupFunction<_CreateNodeN, _CreateNodeD>('wajuce_create_buffer_source');
final _createAnalyser =
    _lib.lookupFunction<_CreateNodeN, _CreateNodeD>('wajuce_create_analyser');
final _createStereoPanner = _lib
    .lookupFunction<_CreateNodeN, _CreateNodeD>('wajuce_create_stereo_panner');
final _createPanner =
    _lib.lookupFunction<_CreateNodeN, _CreateNodeD>('wajuce_create_panner');
final _createWaveShaper = _lib
    .lookupFunction<_CreateNodeN, _CreateNodeD>('wajuce_create_wave_shaper');
final _createConstantSource = _lib.lookupFunction<_CreateNodeN, _CreateNodeD>(
    'wajuce_create_constant_source');
final _createConvolver =
    _lib.lookupFunction<_CreateNodeN, _CreateNodeD>('wajuce_create_convolver');
final _createIIRFilter =
    _lib.lookupFunction<_CreateIIRFilterN, _CreateIIRFilterD>(
        'wajuce_create_iir_filter');
final _createMediaStreamSource =
    _lib.lookupFunction<_CreateNodeN, _CreateNodeD>(
        'wajuce_create_media_stream_source');
final _createMediaStreamDestination =
    _lib.lookupFunction<_CreateNodeN, _CreateNodeD>(
        'wajuce_create_media_stream_destination');
final _createChannelSplitter =
    _lib.lookupFunction<_CreateSplitterN, _CreateSplitterD>(
        'wajuce_create_channel_splitter');
final _createChannelMerger =
    _lib.lookupFunction<_CreateSplitterN, _CreateSplitterD>(
        'wajuce_create_channel_merger');
final _createMachineVoice =
    _lib.lookupFunction<_CreateMachineVoiceN, _CreateMachineVoiceD>(
        'wajuce_create_machine_voice');
final _setMachineVoiceActive =
    _lib.lookupFunction<_SetMachineVoiceActiveN, _SetMachineVoiceActiveD>(
        'wajuce_machine_voice_set_active');

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
final _connect = _lib.lookupFunction<_ConnectN, _ConnectD>('wajuce_connect');
final _connectParam =
    _lib.lookupFunction<_ConnectParamN, _ConnectParamD>('wajuce_connect_param');
final _disconnect =
    _lib.lookupFunction<_DisconnectN, _DisconnectD>('wajuce_disconnect');
final _disconnectOutput =
    _lib.lookupFunction<_DisconnectOutputN, _DisconnectOutputD>(
        'wajuce_disconnect_output');
final _disconnectNodeOutput =
    _lib.lookupFunction<_DisconnectNodeOutputN, _DisconnectNodeOutputD>(
        'wajuce_disconnect_node_output');
final _disconnectNodeInput =
    _lib.lookupFunction<_DisconnectNodeInputN, _DisconnectNodeInputD>(
        'wajuce_disconnect_node_input');
final _disconnectParam =
    _lib.lookupFunction<_DisconnectParamN, _DisconnectParamD>(
        'wajuce_disconnect_param');
final _disconnectAll = _lib
    .lookupFunction<_DisconnectAllN, _DisconnectAllD>('wajuce_disconnect_all');
final _removeNode = _lib
    .lookupFunction<_RemoveNodeN, _RemoveNodeD>('wajuce_context_remove_node');

// Params
final _paramSet =
    _lib.lookupFunction<_ParamSetN, _ParamSetD>('wajuce_param_set');
final _paramSetAtTime = _lib.lookupFunction<_ParamSetAtTimeN, _ParamSetAtTimeD>(
    'wajuce_param_set_at_time');
final _paramLinearRamp =
    _lib.lookupFunction<_ParamRampN, _ParamRampD>('wajuce_param_linear_ramp');
final _paramExpRamp =
    _lib.lookupFunction<_ParamRampN, _ParamRampD>('wajuce_param_exp_ramp');
final _paramSetTarget = _lib.lookupFunction<_ParamSetTargetN, _ParamSetTargetD>(
    'wajuce_param_set_target');
final _paramSetValueCurve =
    _lib.lookupFunction<_ParamSetValueCurveN, _ParamSetValueCurveD>(
        'wajuce_param_set_value_curve');
final _paramCancel =
    _lib.lookupFunction<_ParamCancelN, _ParamCancelD>('wajuce_param_cancel');
final _paramCancelAndHold = _lib.lookupFunction<_ParamCancelN, _ParamCancelD>(
    'wajuce_param_cancel_and_hold');
final _paramGet =
    _lib.lookupFunction<_ParamGetN, _ParamGetD>('wajuce_param_get');

// Osc
final _oscSetType =
    _lib.lookupFunction<_OscSetTypeN, _OscSetTypeD>('wajuce_osc_set_type');
final _oscStart =
    _lib.lookupFunction<_OscStartN, _OscStartD>('wajuce_osc_start');
final _oscStop = _lib.lookupFunction<_OscStartN, _OscStartD>('wajuce_osc_stop');
final _oscSetPeriodicWave =
    _lib.lookupFunction<_OscSetPeriodicWaveN, _OscSetPeriodicWaveD>(
        'wajuce_osc_set_periodic_wave');

// Filter
final _filterSetType = _lib
    .lookupFunction<_FilterSetTypeN, _FilterSetTypeD>('wajuce_filter_set_type');

// BufferSource
final _bufSrcSetBuffer = _lib.lookupFunction<_BufSrcSetBufN, _BufSrcSetBufD>(
    'wajuce_buffer_source_set_buffer');
final _bufSrcStart = _lib
    .lookupFunction<_BufSrcStartN, _BufSrcStartD>('wajuce_buffer_source_start');
final _bufSrcStartAdvanced =
    _lib.lookupFunction<_BufSrcStartAdvancedN, _BufSrcStartAdvancedD>(
        'wajuce_buffer_source_start_with_offset');
final _bufSrcStop = _lib
    .lookupFunction<_BufSrcStopN, _BufSrcStopD>('wajuce_buffer_source_stop');
final _bufSrcSetLoop = _lib.lookupFunction<_BufSrcSetLoopN, _BufSrcSetLoopD>(
    'wajuce_buffer_source_set_loop');
final _bufSrcSetLoopPoints =
    _lib.lookupFunction<_BufSrcSetLoopPointsN, _BufSrcSetLoopPointsD>(
        'wajuce_buffer_source_set_loop_points');

// Analyser
final _analyserSetFft = _lib.lookupFunction<_AnalyserSetFftN, _AnalyserSetFftD>(
    'wajuce_analyser_set_fft_size');
final _analyserSetMinDecibels =
    _lib.lookupFunction<_AnalyserSetDoubleN, _AnalyserSetDoubleD>(
        'wajuce_analyser_set_min_decibels');
final _analyserSetMaxDecibels =
    _lib.lookupFunction<_AnalyserSetDoubleN, _AnalyserSetDoubleD>(
        'wajuce_analyser_set_max_decibels');
final _analyserSetSmoothing =
    _lib.lookupFunction<_AnalyserSetDoubleN, _AnalyserSetDoubleD>(
        'wajuce_analyser_set_smoothing_time_constant');
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
final _biquadGetFrequencyResponse = _lib.lookupFunction<
    _BiquadGetFrequencyResponseN,
    _BiquadGetFrequencyResponseD>('wajuce_biquad_get_frequency_response');
final _iirGetFrequencyResponse = _lib.lookupFunction<
    _BiquadGetFrequencyResponseN,
    _BiquadGetFrequencyResponseD>('wajuce_iir_get_frequency_response');
final _compressorGetReduction =
    _lib.lookupFunction<_CompressorGetReductionN, _CompressorGetReductionD>(
        'wajuce_compressor_get_reduction');
final _pannerSetPanningModel =
    _lib.lookupFunction<_PannerSetIntN, _PannerSetIntD>(
        'wajuce_panner_set_panning_model');
final _pannerSetDistanceModel =
    _lib.lookupFunction<_PannerSetIntN, _PannerSetIntD>(
        'wajuce_panner_set_distance_model');
final _pannerSetRefDistance =
    _lib.lookupFunction<_PannerSetDoubleN, _PannerSetDoubleD>(
        'wajuce_panner_set_ref_distance');
final _pannerSetMaxDistance =
    _lib.lookupFunction<_PannerSetDoubleN, _PannerSetDoubleD>(
        'wajuce_panner_set_max_distance');
final _pannerSetRolloffFactor =
    _lib.lookupFunction<_PannerSetDoubleN, _PannerSetDoubleD>(
        'wajuce_panner_set_rolloff_factor');
final _pannerSetConeInnerAngle =
    _lib.lookupFunction<_PannerSetDoubleN, _PannerSetDoubleD>(
        'wajuce_panner_set_cone_inner_angle');
final _pannerSetConeOuterAngle =
    _lib.lookupFunction<_PannerSetDoubleN, _PannerSetDoubleD>(
        'wajuce_panner_set_cone_outer_angle');
final _pannerSetConeOuterGain =
    _lib.lookupFunction<_PannerSetDoubleN, _PannerSetDoubleD>(
        'wajuce_panner_set_cone_outer_gain');

// WaveShaper
final _waveShaperSetCurve =
    _lib.lookupFunction<_WaveShaperSetCurveN, _WaveShaperSetCurveD>(
        'wajuce_wave_shaper_set_curve');
final _waveShaperSetOversample =
    _lib.lookupFunction<_WaveShaperSetOversampleN, _WaveShaperSetOversampleD>(
        'wajuce_wave_shaper_set_oversample');
final _convolverSetBuffer =
    _lib.lookupFunction<_ConvolverSetBufferN, _ConvolverSetBufferD>(
        'wajuce_convolver_set_buffer');
final _convolverSetNormalize =
    _lib.lookupFunction<_ConvolverSetNormalizeN, _ConvolverSetNormalizeD>(
        'wajuce_convolver_set_normalize');

// MIDI
final _midiGetPortCount =
    _lib.lookupFunction<_MidiGetPortCountN, _MidiGetPortCountD>(
        'wajuce_midi_get_port_count');
final _midiGetPortName =
    _lib.lookupFunction<_MidiGetPortNameN, _MidiGetPortNameD>(
        'wajuce_midi_get_port_name');
final _midiPortOpen = _lib
    .lookupFunction<_MidiPortOpenN, _MidiPortOpenD>('wajuce_midi_port_open');
final _midiPortClose = _lib
    .lookupFunction<_MidiPortOpenN, _MidiPortOpenD>('wajuce_midi_port_close');
final _midiOutputSend = _lib.lookupFunction<_MidiOutputSendN, _MidiOutputSendD>(
    'wajuce_midi_output_send');

// Worklet Bridge
final _createWorkletBridge =
    _lib.lookupFunction<_CreateWorkletBridgeN, _CreateWorkletBridgeD>(
        'wajuce_create_worklet_bridge');
final _workletGetBufferPtr =
    _lib.lookupFunction<_WorkletGetBufN, _WorkletGetBufD>(
        'wajuce_worklet_get_buffer_ptr');
final _workletGetInputChannelCount =
    _lib.lookupFunction<_WorkletGetChannelCountN, _WorkletGetChannelCountD>(
        'wajuce_worklet_get_input_channel_count');
final _workletGetOutputChannelCount =
    _lib.lookupFunction<_WorkletGetChannelCountN, _WorkletGetChannelCountD>(
        'wajuce_worklet_get_output_channel_count');
final _workletGetReadPosValue =
    _lib.lookupFunction<_WorkletGetPosValueN, _WorkletGetPosValueD>(
        'wajuce_worklet_get_read_pos');
final _workletGetWritePosValue =
    _lib.lookupFunction<_WorkletGetPosValueN, _WorkletGetPosValueD>(
        'wajuce_worklet_get_write_pos');
final _workletSetReadPosValue =
    _lib.lookupFunction<_WorkletSetPosValueN, _WorkletSetPosValueD>(
        'wajuce_worklet_set_read_pos');
final _workletSetWritePosValue =
    _lib.lookupFunction<_WorkletSetPosValueN, _WorkletSetPosValueD>(
        'wajuce_worklet_set_write_pos');
final _workletGetCapacity =
    _lib.lookupFunction<_WorkletGetCapN, _WorkletGetCapD>(
        'wajuce_worklet_get_capacity');
final _workletReleaseBridge =
    _lib.lookupFunction<_WorkletReleaseBridgeN, _WorkletReleaseBridgeD>(
        'wajuce_worklet_release_bridge');

typedef _MidiCallbackN = ffi.Void Function(ffi.Int32 portIndex,
    ffi.Pointer<ffi.Uint8> data, ffi.Int32 len, ffi.Double timestamp);
typedef _SetMidiCallbackN = ffi.Void Function(
    ffi.Pointer<ffi.NativeFunction<_MidiCallbackN>>);
typedef _SetMidiCallbackD = void Function(
    ffi.Pointer<ffi.NativeFunction<_MidiCallbackN>>);
final _setMidiCallback =
    _lib.lookupFunction<_SetMidiCallbackN, _SetMidiCallbackD>(
        'wajuce_midi_set_callback');
final _midiDispose = _lib.lookupFunction<ffi.Void Function(), void Function()>(
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

final Map<int, Float64List> _iirFeedforward = <int, Float64List>{};
final Map<int, Float64List> _iirFeedback = <int, Float64List>{};
final Map<int, double> _bufferSourceLoopStarts = <int, double>{};
final Map<int, double> _bufferSourceLoopEnds = <int, double>{};
final Map<int, bool> _convolverNormalize = <int, bool>{};
final Map<int, int> _contextBufferSizes = <int, int>{};
final Map<int, double> _contextSampleRates = <int, double>{};
final Map<int, int> _contextOutputChannels = <int, int>{};

// ---------------------------------------------------------------------------
// Backend API — Context
// ---------------------------------------------------------------------------

int contextCreate(int sampleRate, int bufferSize,
    {int inputChannels = 2, int outputChannels = 2}) {
  // print('[wajuce] Dart: contextCreate sr=$sampleRate, bs=$bufferSize, inCh=$inputChannels, outCh=$outputChannels');
  final id =
      _contextCreate(sampleRate, bufferSize, inputChannels, outputChannels);
  if (id >= 0) {
    _contextBufferSizes[id] = bufferSize;
    _contextSampleRates[id] = sampleRate.toDouble();
    _contextOutputChannels[id] = outputChannels;
  }
  // print('[wajuce] Dart: contextCreated, native id=$id');
  return id;
}

void contextDestroy(int ctxId) {
  _contextBufferSizes.remove(ctxId);
  _contextSampleRates.remove(ctxId);
  _contextOutputChannels.remove(ctxId);
  _contextDestroy(ctxId);
}

double contextGetTime(int ctxId) => _contextGetTime(ctxId);
int contextGetLiveNodeCount(int ctxId) => _contextGetLiveNodeCount(ctxId);
int contextGetFeedbackBridgeCount(int ctxId) =>
    _contextGetFeedbackBridgeCount(ctxId);
int contextGetMachineVoiceGroupCount(int ctxId) =>
    _contextGetMachineVoiceGroupCount(ctxId);
double contextGetSampleRate(int ctxId) => _contextGetSampleRate(ctxId);
int contextGetBitDepth(int ctxId) => _contextGetBitDepth(ctxId);
bool contextSetPreferredSampleRate(int ctxId, double sampleRate) {
  final ok = _contextSetPreferredSampleRate(ctxId, sampleRate) != 0;
  if (ok) {
    _contextSampleRates[ctxId] = sampleRate;
  }
  return ok;
}

bool contextSetPreferredBitDepth(int ctxId, int bitDepth) =>
    _contextSetPreferredBitDepth(ctxId, bitDepth) != 0;
int contextGetState(int ctxId) => _contextGetState(ctxId);
void contextResume(int ctxId) => _contextResume(ctxId);
void contextSuspend(int ctxId) => _contextSuspend(ctxId);
void contextClose(int ctxId) => _contextClose(ctxId);
int contextGetDestinationId(int ctxId) => _contextGetDestinationId(ctxId);
int contextGetListenerId(int ctxId) => _contextGetListenerId(ctxId);
List<Float32List> contextRender(int ctxId, int frames, int channels) {
  if (frames <= 0 || channels <= 0) {
    return List<Float32List>.generate(
        math.max(channels, 0), (_) => Float32List(0));
  }
  final ptr = calloc<ffi.Float>(frames * channels);
  try {
    _contextRender(ctxId, ptr, frames, channels);
    final raw = ptr.asTypedList(frames * channels);
    return List<Float32List>.generate(channels, (ch) {
      final start = ch * frames;
      return Float32List.fromList(raw.sublist(start, start + frames));
    });
  } finally {
    calloc.free(ptr);
  }
}

double contextGetBaseLatency(int ctxId) {
  final bufferSize = _contextBufferSizes[ctxId];
  final sampleRate = _contextSampleRates[ctxId] ?? contextGetSampleRate(ctxId);
  if (bufferSize == null || bufferSize <= 0 || sampleRate <= 0) {
    return 0.0;
  }
  return bufferSize / sampleRate;
}

double contextGetOutputLatency(int ctxId) => contextGetBaseLatency(ctxId);
Object contextGetSinkId(int ctxId) => 'default';
Map<String, double> contextGetOutputTimestamp(int ctxId) => {
      'contextTime': contextGetTime(ctxId),
      'performanceTime': 0.0,
    };
int destinationGetMaxChannelCount(int ctxId) =>
    _contextOutputChannels[ctxId] ?? 2;

int createChannelSplitter(int id, int outputs) =>
    _createChannelSplitter(id, outputs);
int createChannelMerger(int id, int inputs) => _createChannelMerger(id, inputs);

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
int createPanner(int ctxId) {
  return _createPanner(ctxId);
}

int createConstantSource(int ctxId) => _createConstantSource(ctxId);

int createConvolver(int ctxId) => _createConvolver(ctxId);

int createIIRFilter(int ctxId, Float64List feedforward, Float64List feedback) {
  final ff = calloc<ffi.Double>(feedforward.length);
  final fb = calloc<ffi.Double>(feedback.length);
  for (int i = 0; i < feedforward.length; i++) {
    ff[i] = feedforward[i];
  }
  for (int i = 0; i < feedback.length; i++) {
    fb[i] = feedback[i];
  }
  final id =
      _createIIRFilter(ctxId, ff, feedforward.length, fb, feedback.length);
  calloc.free(ff);
  calloc.free(fb);
  if (id >= 0) {
    _iirFeedforward[id] = Float64List.fromList(feedforward);
    _iirFeedback[id] = Float64List.fromList(feedback);
  }
  return id;
}

int createMediaStreamSource(int ctxId, [dynamic stream]) =>
    _createMediaStreamSource(ctxId);
int createMediaStreamDestination(int ctxId) =>
    _createMediaStreamDestination(ctxId);
int createMediaElementSource(int ctxId, [dynamic mediaElement]) =>
    _createMediaStreamSource(ctxId);
int createMediaStreamTrackSource(int ctxId, [dynamic mediaStreamTrack]) =>
    _createMediaStreamSource(ctxId);
int createScriptProcessor(
    int ctxId, int bufferSize, int inChannels, int outChannels) {
  final inputs = inChannels > 0 ? inChannels : 2;
  final outputs = outChannels > 0 ? outChannels : 2;
  return _createWorkletBridge(ctxId, inputs, outputs);
}

List<int> createMachineVoice(int ctxId) {
  final ptr = calloc<ffi.Int32>(7);
  _createMachineVoice(ctxId, ptr);
  final result = List<int>.from(ptr.asTypedList(7));
  calloc.free(ptr);
  return result;
}

void setMachineVoiceActive(int ctxId, int nodeId, bool active) {
  _setMachineVoiceActive(ctxId, nodeId, active ? 1 : 0);
}

// ---------------------------------------------------------------------------
// Backend API — Graph
// ---------------------------------------------------------------------------

void connect(int ctxId, int srcId, int dstId, int output, int input) {
  _connect(ctxId, srcId, dstId, output, input);
}

void connectParam(
    int ctxId, int srcId, int dstId, String paramName, int output) {
  final namePtr = paramName.toNativeUtf8().cast<ffi.Char>();
  _connectParam(ctxId, srcId, dstId, namePtr, output);
  calloc.free(namePtr);
}

void disconnect(int ctxId, int srcId, int dstId) {
  _disconnect(ctxId, srcId, dstId);
}

void disconnectOutput(int ctxId, int srcId, int output) {
  _disconnectOutput(ctxId, srcId, output);
}

void disconnectNodeOutput(int ctxId, int srcId, int dstId, int output) {
  _disconnectNodeOutput(ctxId, srcId, dstId, output);
}

void disconnectNodeInput(
    int ctxId, int srcId, int dstId, int output, int input) {
  _disconnectNodeInput(ctxId, srcId, dstId, output, input);
}

void disconnectParam(
    int ctxId, int srcId, int dstId, String paramName, int output) {
  final namePtr = paramName.toNativeUtf8().cast<ffi.Char>();
  _disconnectParam(ctxId, srcId, dstId, namePtr, output);
  calloc.free(namePtr);
}

void disconnectAll(int ctxId, int srcId) {
  _disconnectAll(ctxId, srcId);
}

void removeNode(int ctxId, int nodeId) {
  _iirFeedforward.remove(nodeId);
  _iirFeedback.remove(nodeId);
  _bufferSourceLoopStarts.remove(nodeId);
  _bufferSourceLoopEnds.remove(nodeId);
  _convolverNormalize.remove(nodeId);
  _removeNode(ctxId, nodeId);
}

// ---------------------------------------------------------------------------
// Backend API — AudioParam
// ---------------------------------------------------------------------------

void paramSet(int nodeId, String paramName, double value) {
  if (nodeId < 0) {
    return;
  }
  final p = _toCString(paramName);
  _paramSet(nodeId, p, value);
  _freeCString(p);
}

void paramSetAtTime(int nodeId, String paramName, double value, double time) {
  if (nodeId < 0) {
    return;
  }
  final p = _toCString(paramName);
  _paramSetAtTime(nodeId, p, value, time);
  _freeCString(p);
}

void paramLinearRamp(
    int nodeId, String paramName, double value, double endTime) {
  if (nodeId < 0) {
    return;
  }
  final p = _toCString(paramName);
  _paramLinearRamp(nodeId, p, value, endTime);
  _freeCString(p);
}

void paramExpRamp(int nodeId, String paramName, double value, double endTime) {
  if (nodeId < 0) {
    return;
  }
  final p = _toCString(paramName);
  _paramExpRamp(nodeId, p, value, endTime);
  _freeCString(p);
}

void paramSetTarget(
    int nodeId, String paramName, double target, double startTime, double tc) {
  if (nodeId < 0) {
    return;
  }
  final p = _toCString(paramName);
  _paramSetTarget(nodeId, p, target, startTime, tc);
  _freeCString(p);
}

void paramCancel(int nodeId, String paramName, double cancelTime) {
  if (nodeId < 0) {
    return;
  }
  final p = _toCString(paramName);
  _paramCancel(nodeId, p, cancelTime);
  _freeCString(p);
}

void paramCancelAndHold(int nodeId, String paramName, double time) {
  if (nodeId < 0) {
    return;
  }
  final p = _toCString(paramName);
  _paramCancelAndHold(nodeId, p, time);
  _freeCString(p);
}

void paramSetValueCurve(int nodeId, String paramName, Float32List values,
    double startTime, double duration) {
  if (nodeId < 0) {
    return;
  }
  if (values.isEmpty || duration <= 0) {
    return;
  }
  final p = _toCString(paramName);
  final nativeValues = calloc<ffi.Float>(values.length);
  nativeValues.asTypedList(values.length).setAll(0, values);
  _paramSetValueCurve(
      nodeId, p, nativeValues, values.length, startTime, duration);
  calloc.free(nativeValues);
  _freeCString(p);
}

double paramGet(int nodeId, String paramName) {
  if (nodeId < 0) {
    return 0.0;
  }
  final p = _toCString(paramName);
  final value = _paramGet(nodeId, p);
  _freeCString(p);
  return value;
}

// ---------------------------------------------------------------------------
// Backend API — Oscillator
// ---------------------------------------------------------------------------

void oscSetType(int nodeId, int type) => _oscSetType(nodeId, type);
void oscStart(int nodeId, double when) => _oscStart(nodeId, when);
void oscStop(int nodeId, double when) => _oscStop(nodeId, when);

// PeriodicWave support
void oscSetPeriodicWave(int nodeId, Float32List real, Float32List imag, int len,
    bool disableNormalization) {
  using((arena) {
    final pReal = arena<ffi.Float>(len);
    final pImag = arena<ffi.Float>(len);
    for (int i = 0; i < len; i++) {
      pReal[i] = real[i];
      pImag[i] = imag[i];
    }
    _oscSetPeriodicWave(
        nodeId, pReal, pImag, len, disableNormalization ? 1 : 0);
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
  _bufSrcSetBuffer(
      nodeId, nativeData, frames, channels, buffer.sampleRate.toInt());
  calloc.free(nativeData);
}

void bufferSourceStart(int nodeId, [double when = 0]) {
  _bufSrcStart(nodeId, when);
}

void bufferSourceStartAdvanced(int nodeId, double when,
    [double offset = 0, double? duration]) {
  _bufSrcStartAdvanced(
      nodeId, when, offset, duration ?? 0.0, duration == null ? 0 : 1);
}

void bufferSourceStop(int nodeId, [double when = 0]) {
  _bufSrcStop(nodeId, when);
}

void bufferSourceSetLoop(int nodeId, bool loop) {
  _bufSrcSetLoop(nodeId, loop ? 1 : 0);
}

void bufferSourceSetLoopStart(int nodeId, double loopStart) {
  final previousEnd = _bufferSourceLoopEnds[nodeId] ?? 0.0;
  _bufferSourceLoopStarts[nodeId] = loopStart;
  _bufSrcSetLoopPoints(nodeId, loopStart, previousEnd);
}

void bufferSourceSetLoopEnd(int nodeId, double loopEnd) {
  final previousStart = _bufferSourceLoopStarts[nodeId] ?? 0.0;
  _bufferSourceLoopEnds[nodeId] = loopEnd;
  _bufSrcSetLoopPoints(nodeId, previousStart, loopEnd);
}

// ---------------------------------------------------------------------------
// Backend API — Analyser
// ---------------------------------------------------------------------------

void analyserSetFftSize(int nodeId, int size) {
  _analyserSetFft(nodeId, size);
}

void analyserSetMinDecibels(int nodeId, double value) {
  _analyserSetMinDecibels(nodeId, value);
}

void analyserSetMaxDecibels(int nodeId, double value) {
  _analyserSetMaxDecibels(nodeId, value);
}

void analyserSetSmoothingTimeConstant(int nodeId, double value) {
  _analyserSetSmoothing(nodeId, value);
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

void biquadGetFrequencyResponse(int nodeId, Float32List frequencyHz,
    Float32List magResponse, Float32List phaseResponse) {
  final count = frequencyHz.length;
  final freq = calloc<ffi.Float>(count);
  final mag = calloc<ffi.Float>(count);
  final phase = calloc<ffi.Float>(count);
  for (int i = 0; i < count; i++) {
    freq[i] = frequencyHz[i];
  }
  _biquadGetFrequencyResponse(nodeId, freq, mag, phase, count);
  magResponse.setAll(0, mag.asTypedList(count));
  phaseResponse.setAll(0, phase.asTypedList(count));
  calloc.free(freq);
  calloc.free(mag);
  calloc.free(phase);
}

double compressorGetReduction(int nodeId) {
  return _compressorGetReduction(nodeId);
}

void constantSourceStart(int nodeId, double when) {
  _oscStart(nodeId, when);
}

void constantSourceStop(int nodeId, double when) {
  _oscStop(nodeId, when);
}

void convolverSetBuffer(int nodeId, WABuffer? buffer) {
  if (buffer == null) {
    _convolverSetBuffer(nodeId, ffi.nullptr, 0, 0, 0, 1);
    return;
  }
  final channels = buffer.numberOfChannels;
  final frames = buffer.length;
  final totalSamples = frames * channels;
  final nativeData = calloc<ffi.Float>(totalSamples);
  for (int ch = 0; ch < channels; ch++) {
    final channelData = buffer.getChannelData(ch);
    for (int i = 0; i < frames; i++) {
      nativeData[ch * frames + i] = channelData[i];
    }
  }
  final normalize = _convolverNormalize[nodeId] ?? true;
  _convolverSetBuffer(nodeId, nativeData, frames, channels,
      buffer.sampleRate.toInt(), normalize ? 1 : 0);
  calloc.free(nativeData);
}

void convolverSetNormalize(int nodeId, bool normalize) {
  _convolverNormalize[nodeId] = normalize;
  _convolverSetNormalize(nodeId, normalize ? 1 : 0);
}

void iirGetFrequencyResponse(int nodeId, Float32List frequencyHz,
    Float32List magResponse, Float32List phaseResponse) {
  final count = math.min(
      frequencyHz.length, math.min(magResponse.length, phaseResponse.length));
  if (count <= 0) return;
  final freq = calloc<ffi.Float>(count);
  final mag = calloc<ffi.Float>(count);
  final phase = calloc<ffi.Float>(count);
  for (int i = 0; i < count; i++) {
    freq[i] = frequencyHz[i];
  }
  _iirGetFrequencyResponse(nodeId, freq, mag, phase, count);
  magResponse.setAll(0, mag.asTypedList(count));
  phaseResponse.setAll(0, phase.asTypedList(count));
  calloc.free(freq);
  calloc.free(mag);
  calloc.free(phase);
}

void pannerSetPanningModel(int nodeId, int model) {
  _pannerSetPanningModel(nodeId, model);
}

void pannerSetDistanceModel(int nodeId, int model) {
  _pannerSetDistanceModel(nodeId, model);
}

void pannerSetRefDistance(int nodeId, double value) {
  _pannerSetRefDistance(nodeId, value);
}

void pannerSetMaxDistance(int nodeId, double value) {
  _pannerSetMaxDistance(nodeId, value);
}

void pannerSetRolloffFactor(int nodeId, double value) {
  _pannerSetRolloffFactor(nodeId, value);
}

void pannerSetConeInnerAngle(int nodeId, double value) {
  _pannerSetConeInnerAngle(nodeId, value);
}

void pannerSetConeOuterAngle(int nodeId, double value) {
  _pannerSetConeOuterAngle(nodeId, value);
}

void pannerSetConeOuterGain(int nodeId, double value) {
  _pannerSetConeOuterGain(nodeId, value);
}

dynamic mediaStreamSourceGetStream(int nodeId) => null;
dynamic mediaStreamDestinationGetStream(int nodeId) => null;

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
  final res = _decodeAudioData(encodedDataPtr, data.length,
      ffi.Pointer.fromAddress(0), framesPtr, channelsPtr, srPtr);

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
  _decodeAudioData(
      encodedDataPtr, data.length, outDataPtr, framesPtr, channelsPtr, srPtr);

  final buffer = WABuffer(
    numberOfChannels: channels,
    length: frames,
    sampleRate: sampleRate.toDouble(),
  );

  final flatData = outDataPtr.asTypedList(frames * channels);
  for (int ch = 0; ch < channels; ch++) {
    final channelData =
        Float32List.fromList(flatData.sublist(ch * frames, (ch + 1) * frames));
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

Future<Object?> getWebMicrophoneStream() async => null;

Future<void> webInitializeWorklet(int ctxId) async {
  // No-op on native
}

Future<void> webAddWorkletModule(int ctxId, String moduleIdentifier) async {
  // No-op on native
}

int createWorkletNode(
    int ctxId, String processorName, int numInputs, int numOutputs,
    {bool useProxyProcessor = false}) {
  return _createWorkletBridge(ctxId, numInputs, numOutputs);
}

ffi.Pointer<ffi.Float> workletGetBufferPtr(
        int ctxId, int bridgeId, int direction, int channel) =>
    _workletGetBufferPtr(ctxId, bridgeId, direction, channel);

int workletGetInputChannelCount(int ctxId, int bridgeId) =>
    _workletGetInputChannelCount(ctxId, bridgeId);

int workletGetOutputChannelCount(int ctxId, int bridgeId) =>
    _workletGetOutputChannelCount(ctxId, bridgeId);

int workletGetReadPos(int ctxId, int bridgeId, int direction, int channel) =>
    _workletGetReadPosValue(ctxId, bridgeId, direction, channel);

int workletGetWritePos(int ctxId, int bridgeId, int direction, int channel) =>
    _workletGetWritePosValue(ctxId, bridgeId, direction, channel);

void workletSetReadPos(
        int ctxId, int bridgeId, int direction, int channel, int value) =>
    _workletSetReadPosValue(ctxId, bridgeId, direction, channel, value);

void workletSetWritePos(
        int ctxId, int bridgeId, int direction, int channel, int value) =>
    _workletSetWritePosValue(ctxId, bridgeId, direction, channel, value);

int workletGetCapacity(int ctxId, int bridgeId) =>
    _workletGetCapacity(ctxId, bridgeId);

void workletReleaseBridge(int ctxId, int bridgeId) =>
    _workletReleaseBridge(ctxId, bridgeId);
void workletPostMessage(int nodeId, dynamic message) {
  // Native routing is handled by the Dart audio isolate manager.
}
bool workletSupportsExternalProcessors() => false;

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
  // On native platforms, MIDI access is available when the runtime driver exists.
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

void Function(int nodeId)? onWebProcessQuantum;
void Function(int nodeId, dynamic data)? onWebWorkletMessage;

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
