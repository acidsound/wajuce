// ignore_for_file: public_member_api_docs
/// Stub Backend — fallback for unsupported platforms.
///
/// All functions throw UnsupportedError. Used when neither
/// dart:ffi (native) nor dart:js_interop (web) is available.
library;

import 'dart:typed_data';

import '../audio_buffer.dart';

Never _unsupported() =>
    throw UnsupportedError('wajuce is not supported on this platform');

// ---------------------------------------------------------------------------
// Context
// ---------------------------------------------------------------------------

int contextCreate(int sampleRate, int bufferSize,
        {int inputChannels = 2, int outputChannels = 2}) =>
    _unsupported();
void contextDestroy(int ctxId) => _unsupported();
double contextGetTime(int ctxId) => _unsupported();
double contextGetSampleRate(int ctxId) => _unsupported();
int contextGetState(int ctxId) => _unsupported();
void contextResume(int ctxId) => _unsupported();
void contextSuspend(int ctxId) => _unsupported();
void contextClose(int ctxId) => _unsupported();
int contextGetDestinationId(int ctxId) => _unsupported();
int contextGetListenerId(int ctxId) => _unsupported();
double contextGetBaseLatency(int ctxId) => 0.0;
double contextGetOutputLatency(int ctxId) => 0.0;
Object contextGetSinkId(int ctxId) => 'default';
Map<String, double> contextGetOutputTimestamp(int ctxId) =>
    const {'contextTime': 0.0, 'performanceTime': 0.0};
int destinationGetMaxChannelCount(int ctxId) => 2;

// ---------------------------------------------------------------------------
// Node Factory
// ---------------------------------------------------------------------------

int createGain(int ctxId) => _unsupported();
int createOscillator(int ctxId) => _unsupported();
int createBiquadFilter(int ctxId) => _unsupported();
int createCompressor(int ctxId) => _unsupported();
int createDelay(int ctxId, double maxDelay) => _unsupported();
int createBufferSource(int ctxId) => _unsupported();
int createAnalyser(int ctxId) => _unsupported();
int createStereoPanner(int ctxId) => _unsupported();
int createPanner(int ctxId) => _unsupported();
int createWaveShaper(int ctxId) => _unsupported();
int createConstantSource(int ctxId) => _unsupported();
int createConvolver(int ctxId) => _unsupported();
int createIIRFilter(int ctxId, Float64List feedforward, Float64List feedback) =>
    _unsupported();
int createMediaStreamSource(int ctxId, [dynamic stream]) => _unsupported();
int createMediaStreamDestination(int ctxId) => _unsupported();
int createMediaElementSource(int ctxId, [dynamic mediaElement]) =>
    _unsupported();
int createMediaStreamTrackSource(int ctxId, [dynamic mediaStreamTrack]) =>
    _unsupported();
int createScriptProcessor(
        int ctxId, int bufferSize, int inChannels, int outChannels) =>
    _unsupported();
int createChannelSplitter(int ctxId, int outputs) => _unsupported();
int createChannelMerger(int ctxId, int inputs) => _unsupported();
List<int> createMachineVoice(int ctxId) => _unsupported();

// ---------------------------------------------------------------------------
// Graph
// ---------------------------------------------------------------------------

void connect(int ctxId, int srcId, int dstId, int output, int input) =>
    _unsupported();
void disconnect(int ctxId, int srcId, int dstId) => _unsupported();
void disconnectAll(int ctxId, int srcId) {}
void removeNode(int ctxId, int nodeId) {}

// ---------------------------------------------------------------------------
// AudioParam
// ---------------------------------------------------------------------------

void paramSet(int nodeId, String paramName, double value) => _unsupported();
void paramSetAtTime(int nodeId, String paramName, double value, double time) =>
    _unsupported();
void paramLinearRamp(
        int nodeId, String paramName, double value, double endTime) =>
    _unsupported();
void paramExpRamp(int nodeId, String paramName, double value, double endTime) =>
    _unsupported();
void paramSetTarget(int nodeId, String paramName, double target,
        double startTime, double tc) =>
    _unsupported();
void paramCancel(int nodeId, String paramName, double cancelTime) =>
    _unsupported();
void paramCancelAndHold(int nodeId, String paramName, double time) =>
    _unsupported();
void paramSetValueCurve(int nodeId, String paramName, Float32List values,
        double startTime, double duration) =>
    _unsupported();

// ---------------------------------------------------------------------------
// Oscillator
// ---------------------------------------------------------------------------

void oscSetType(int nodeId, int type) => _unsupported();
void oscStart(int nodeId, double when) => _unsupported();
void oscStop(int nodeId, double when) => _unsupported();
void oscSetPeriodicWave(
        int nodeId, Float32List real, Float32List imag, int len) =>
    _unsupported();

// ---------------------------------------------------------------------------
// Filter
// ---------------------------------------------------------------------------

void filterSetType(int nodeId, int type) => _unsupported();

// ---------------------------------------------------------------------------
// BufferSource
// ---------------------------------------------------------------------------

void bufferSourceSetBuffer(int nodeId, WABuffer buffer) => _unsupported();
void bufferSourceStart(int nodeId, [double when = 0]) => _unsupported();
void bufferSourceStartAdvanced(int nodeId, double when,
        [double offset = 0, double? duration]) =>
    _unsupported();
void bufferSourceStop(int nodeId, [double when = 0]) => _unsupported();
void bufferSourceSetLoop(int nodeId, bool loop) => _unsupported();
void bufferSourceSetLoopStart(int nodeId, double loopStart) => _unsupported();
void bufferSourceSetLoopEnd(int nodeId, double loopEnd) => _unsupported();

// ---------------------------------------------------------------------------
// Analyser
// ---------------------------------------------------------------------------

void analyserSetFftSize(int nodeId, int size) => _unsupported();
void analyserSetMinDecibels(int nodeId, double value) => _unsupported();
void analyserSetMaxDecibels(int nodeId, double value) => _unsupported();
void analyserSetSmoothingTimeConstant(int nodeId, double value) =>
    _unsupported();
Uint8List analyserGetByteFrequencyData(int nodeId, int len) => _unsupported();
Uint8List analyserGetByteTimeDomainData(int nodeId, int len) => _unsupported();
Float32List analyserGetFloatFrequencyData(int nodeId, int len) =>
    _unsupported();
Float32List analyserGetFloatTimeDomainData(int nodeId, int len) =>
    _unsupported();

void biquadGetFrequencyResponse(int nodeId, Float32List frequencyHz,
        Float32List magResponse, Float32List phaseResponse) =>
    _unsupported();

double compressorGetReduction(int nodeId) => 0.0;

void constantSourceStart(int nodeId, double when) => _unsupported();
void constantSourceStop(int nodeId, double when) => _unsupported();

void convolverSetBuffer(int nodeId, WABuffer? buffer) => _unsupported();
void convolverSetNormalize(int nodeId, bool normalize) => _unsupported();

void iirGetFrequencyResponse(int nodeId, Float32List frequencyHz,
        Float32List magResponse, Float32List phaseResponse) =>
    _unsupported();

void pannerSetPanningModel(int nodeId, int model) => _unsupported();
void pannerSetDistanceModel(int nodeId, int model) => _unsupported();
void pannerSetRefDistance(int nodeId, double value) => _unsupported();
void pannerSetMaxDistance(int nodeId, double value) => _unsupported();
void pannerSetRolloffFactor(int nodeId, double value) => _unsupported();
void pannerSetConeInnerAngle(int nodeId, double value) => _unsupported();
void pannerSetConeOuterAngle(int nodeId, double value) => _unsupported();
void pannerSetConeOuterGain(int nodeId, double value) => _unsupported();

dynamic mediaStreamSourceGetStream(int nodeId) => null;
dynamic mediaStreamDestinationGetStream(int nodeId) => null;

// ---------------------------------------------------------------------------
// WaveShaper
// ---------------------------------------------------------------------------

void waveShaperSetCurve(int nodeId, Float32List curve) => _unsupported();
void waveShaperSetOversample(int nodeId, int type) => _unsupported();

// ---------------------------------------------------------------------------
// Buffer
// ---------------------------------------------------------------------------

int createBuffer(int numberOfChannels, int length, int sampleRate) =>
    _unsupported();
WABuffer? getBuffer(int bufferId) => _unsupported();
Future<WABuffer> decodeAudioData(int ctxId, Uint8List data) => _unsupported();

// ---------------------------------------------------------------------------
// WorkletBridge (Phase 8)
// ---------------------------------------------------------------------------

Future<Object?> getWebMicrophoneStream() async => null;

Future<void> webInitializeWorklet(int ctxId) async {}

Future<void> webAddWorkletModule(int ctxId, String moduleIdentifier) async {}

int createWorkletNode(
        int ctxId, String processorName, int numInputs, int numOutputs,
        {bool useProxyProcessor = false}) =>
    _unsupported();

int workletGetCapacity(int bridgeId) => _unsupported();
int workletGetBufferPtr(int bridgeId, int type, int channel) => _unsupported();
int workletGetReadPosPtr(int bridgeId, int type, int channel) => _unsupported();
int workletGetWritePosPtr(int bridgeId, int type, int channel) =>
    _unsupported();
int workletGetReadPos(int bridgeId, int type, int channel) => _unsupported();
int workletGetWritePos(int bridgeId, int type, int channel) => _unsupported();
void workletSetReadPos(int bridgeId, int type, int channel, int value) =>
    _unsupported();
void workletSetWritePos(int bridgeId, int type, int channel, int value) =>
    _unsupported();
void workletPostMessage(int nodeId, dynamic message) => _unsupported();
bool workletSupportsExternalProcessors() => false;

// ---------------------------------------------------------------------------
// MIDI
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

void Function(int portIndex, Uint8List data, double timestamp)?
    onMidiMessageReceived;

void Function(int nodeId)? onWebProcessQuantum;
void Function(int nodeId, dynamic data)? onWebWorkletMessage;

Future<bool> midiRequestAccess({bool sysex = false}) => _unsupported();
Future<MidiDeviceInfoBackend> midiGetDevices() => _unsupported();
void midiInputOpen(int portIndex) => _unsupported();
void midiInputClose(int portIndex) => _unsupported();
void midiOutputOpen(int portIndex) => _unsupported();
void midiOutputClose(int portIndex) => _unsupported();
void midiOutputSend(int portIndex, Uint8List data, double timestamp) =>
    _unsupported();
void midiDispose() => _unsupported();
