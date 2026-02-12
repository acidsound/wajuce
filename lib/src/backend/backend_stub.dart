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
int createWaveShaper(int ctxId) => _unsupported();
int createMediaStreamSource(int ctxId, [dynamic stream]) => _unsupported();
int createMediaStreamDestination(int ctxId) => _unsupported();
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

// ---------------------------------------------------------------------------
// Oscillator
// ---------------------------------------------------------------------------

void oscSetType(int nodeId, int type) => _unsupported();
void oscStart(int nodeId, double when) => _unsupported();
void oscStop(int nodeId, double when) => _unsupported();
void oscSetPeriodicWave(int nodeId, Float32List real, Float32List imag, int len) => _unsupported();

// ---------------------------------------------------------------------------
// Filter
// ---------------------------------------------------------------------------

void filterSetType(int nodeId, int type) => _unsupported();

// ---------------------------------------------------------------------------
// BufferSource
// ---------------------------------------------------------------------------

void bufferSourceSetBuffer(int nodeId, WABuffer buffer) => _unsupported();
void bufferSourceStart(int nodeId, [double when = 0]) => _unsupported();
void bufferSourceStop(int nodeId, [double when = 0]) => _unsupported();
void bufferSourceSetLoop(int nodeId, bool loop) => _unsupported();

// ---------------------------------------------------------------------------
// Analyser
// ---------------------------------------------------------------------------

void analyserSetFftSize(int nodeId, int size) => _unsupported();
Uint8List analyserGetByteFrequencyData(int nodeId, int len) => _unsupported();
Uint8List analyserGetByteTimeDomainData(int nodeId, int len) => _unsupported();
Float32List analyserGetFloatFrequencyData(int nodeId, int len) =>
    _unsupported();
Float32List analyserGetFloatTimeDomainData(int nodeId, int len) =>
    _unsupported();

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

int createWorkletNode(int ctxId, int numInputs, int numOutputs) =>
    _unsupported();

int workletGetCapacity(int bridgeId) => _unsupported();
int workletGetBufferPtr(int bridgeId, int type, int channel) => _unsupported();
int workletGetReadPosPtr(int bridgeId, int type, int channel) => _unsupported();
int workletGetWritePosPtr(int bridgeId, int type, int channel) => _unsupported();

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

void Function(int portIndex, Uint8List data, double timestamp)? onMidiMessageReceived;

Future<bool> midiRequestAccess({bool sysex = false}) => _unsupported();
Future<MidiDeviceInfoBackend> midiGetDevices() => _unsupported();
void midiInputOpen(int portIndex) => _unsupported();
void midiInputClose(int portIndex) => _unsupported();
void midiOutputOpen(int portIndex) => _unsupported();
void midiOutputClose(int portIndex) => _unsupported();
void midiOutputSend(int portIndex, Uint8List data, double timestamp) =>
    _unsupported();
void midiDispose() => _unsupported();
