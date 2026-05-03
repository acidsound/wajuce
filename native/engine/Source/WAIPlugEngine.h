#pragma once

#include "ParamAutomation.h"
#include "RingBuffer.h"

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#if defined(WAJUCE_USE_RTAUDIO) && WAJUCE_USE_RTAUDIO
#include "RtAudio.h"
#endif

#if defined(__APPLE__)
#include <TargetConditionals.h>
#if TARGET_OS_IPHONE && !(defined(WAJUCE_USE_RTAUDIO) && WAJUCE_USE_RTAUDIO)
#ifndef WAJUCE_USE_APPLE_AUDIOUNIT
#define WAJUCE_USE_APPLE_AUDIOUNIT 1
#endif
#endif
#endif

#if defined(WAJUCE_USE_APPLE_AUDIOUNIT) && WAJUCE_USE_APPLE_AUDIOUNIT
#include <AudioUnit/AudioUnit.h>
#endif

namespace wajuce {

struct WorkletBridgeState {
  int32_t inputChannels = 0;
  int32_t outputChannels = 0;
  int32_t capacity = 0;
  std::shared_ptr<MultiChannelSPSCRingBuffer> toIsolate;
  std::shared_ptr<MultiChannelSPSCRingBuffer> fromIsolate;
  std::atomic<bool> active{true};
  std::atomic<int64_t> droppedInputSamples{0};
  std::atomic<int64_t> outputUnderrunSamples{0};
};

class Engine : public std::enable_shared_from_this<Engine> {
public:
  Engine(double sampleRate = 44100.0, int bufferSize = 512,
         int inputChannels = 2, int outputChannels = 2);
  ~Engine();

  void resume();
  void suspend();
  void close();

  int getState() const { return state.load(std::memory_order_relaxed); }
  double getCurrentTime() const {
    return currentTime.load(std::memory_order_relaxed);
  }
  double getSampleRate() const {
    return sampleRate.load(std::memory_order_relaxed);
  }
  int getCurrentBitDepth() const {
    return preferredBitDepth.load(std::memory_order_relaxed);
  }
  int32_t getDestinationId() const { return 0; }
  int32_t getListenerId() const { return listenerNodeId; }
  int32_t getLiveNodeCount();
  int32_t getFeedbackBridgeCount() const { return feedbackCycleCount.load(); }
  int32_t getMachineVoiceGroupCount();
  bool setPreferredSampleRate(double preferredSampleRate);
  bool setPreferredBitDepth(int preferredBitDepth);

  int32_t createGain();
  int32_t createOscillator();
  int32_t createBiquadFilter();
  int32_t createCompressor();
  int32_t createDelay(float maxDelay);
  int32_t createBufferSource();
  int32_t createAnalyser();
  int32_t createStereoPanner();
  int32_t createPanner();
  int32_t createWaveShaper();
  int32_t createConstantSource();
  int32_t createConvolver();
  int32_t createIIRFilter(const double *feedforward, int32_t feedforwardLen,
                          const double *feedback, int32_t feedbackLen);
  int32_t createChannelSplitter(int32_t outputs);
  int32_t createChannelMerger(int32_t inputs);
  int32_t createMediaStreamSource();
  int32_t createMediaStreamDestination();
  int32_t createWorkletBridge(int32_t inputs, int32_t outputs);
  void createMachineVoice(int32_t *resultIds);
  void removeNode(int32_t nodeId);

  void connect(int32_t srcId, int32_t dstId, int output, int input);
  void connectParam(int32_t srcId, int32_t dstId, const char *param,
                    int output);
  void disconnect(int32_t srcId, int32_t dstId);
  void disconnectOutput(int32_t srcId, int output);
  void disconnectNodeOutput(int32_t srcId, int32_t dstId, int output);
  void disconnectNodeInput(int32_t srcId, int32_t dstId, int output,
                           int input);
  void disconnectParam(int32_t srcId, int32_t dstId, const char *param,
                       int output);
  void disconnectAll(int32_t srcId);
  bool containsNode(int32_t nodeId);

  void paramSet(int32_t nodeId, const char *param, float value);
  void paramSetAtTime(int32_t nodeId, const char *param, float value,
                      double time);
  void paramLinearRamp(int32_t nodeId, const char *param, float value,
                       double endTime);
  void paramExpRamp(int32_t nodeId, const char *param, float value,
                    double endTime);
  void paramSetTarget(int32_t nodeId, const char *param, float target,
                      double startTime, float tc);
  void paramCancel(int32_t nodeId, const char *param, double cancelTime);
  void paramCancelAndHold(int32_t nodeId, const char *param, double time);
  void paramSetValueCurve(int32_t nodeId, const char *param, const float *values,
                          int32_t length, double startTime, double duration);
  float paramGet(int32_t nodeId, const char *param);

  void oscSetType(int32_t nodeId, int type);
  void oscStart(int32_t nodeId, double when);
  void oscStop(int32_t nodeId, double when);
  void oscSetPeriodicWave(int32_t nodeId, const float *real, const float *imag,
                          int32_t len, bool disableNormalization);

  void filterSetType(int32_t nodeId, int type);

  void bufferSourceSetBuffer(int32_t nodeId, const float *data, int32_t frames,
                             int32_t channels, int32_t sr);
  void bufferSourceStart(int32_t nodeId, double when);
  void bufferSourceStart(int32_t nodeId, double when, double offset,
                         double duration, bool hasDuration);
  void bufferSourceStop(int32_t nodeId, double when);
  void bufferSourceSetLoop(int32_t nodeId, bool loop);
  void bufferSourceSetLoopPoints(int32_t nodeId, double loopStart,
                                 double loopEnd);

  void analyserSetFftSize(int32_t nodeId, int32_t size);
  void analyserSetMinDecibels(int32_t nodeId, double value);
  void analyserSetMaxDecibels(int32_t nodeId, double value);
  void analyserSetSmoothingTimeConstant(int32_t nodeId, double value);
  void analyserGetByteFreqData(int32_t nodeId, uint8_t *data, int32_t len);
  void analyserGetByteTimeData(int32_t nodeId, uint8_t *data, int32_t len);
  void analyserGetFloatFreqData(int32_t nodeId, float *data, int32_t len);
  void analyserGetFloatTimeData(int32_t nodeId, float *data, int32_t len);
  void biquadGetFrequencyResponse(int32_t nodeId, const float *frequencyHz,
                                  float *magResponse, float *phaseResponse,
                                  int32_t len);
  void iirGetFrequencyResponse(int32_t nodeId, const float *frequencyHz,
                               float *magResponse, float *phaseResponse,
                               int32_t len);
  float compressorGetReduction(int32_t nodeId);
  void pannerSetPanningModel(int32_t nodeId, int model);
  void pannerSetDistanceModel(int32_t nodeId, int model);
  void pannerSetRefDistance(int32_t nodeId, double value);
  void pannerSetMaxDistance(int32_t nodeId, double value);
  void pannerSetRolloffFactor(int32_t nodeId, double value);
  void pannerSetConeInnerAngle(int32_t nodeId, double value);
  void pannerSetConeOuterAngle(int32_t nodeId, double value);
  void pannerSetConeOuterGain(int32_t nodeId, double value);

  void waveShaperSetCurve(int32_t nodeId, const float *data, int32_t len);
  void waveShaperSetOversample(int32_t nodeId, int type);
  void convolverSetBuffer(int32_t nodeId, const float *data, int32_t frames,
                          int32_t channels, int32_t sr, bool normalize);
  void convolverSetNormalize(int32_t nodeId, bool normalize);
  void requestMediaInput();

  std::shared_ptr<WorkletBridgeState> getWorkletBridgeState(int32_t nodeId);
  int32_t getWorkletBridgeInputChannelCount(int32_t nodeId);
  int32_t getWorkletBridgeOutputChannelCount(int32_t nodeId);
  int32_t getWorkletBridgeCapacity(int32_t nodeId);
  void releaseWorkletBridge(int32_t nodeId);

  int32_t render(float *outData, int32_t frames, int32_t channels);
  void setRealtimeInputInterleaved(const float *input, int frames, int channels);
  void setRealtimeInputPlanar(const float *input, int frames, int channels);
  void setMachineVoiceActive(int32_t nodeId, bool active);

public:
  struct AudioBus {
    int channels = 0;
    int frames = 0;
    std::vector<float> samples;

    void resize(int nextChannels, int nextFrames);
    void clear();
    float *channel(int ch);
    const float *channel(int ch) const;
  };

  enum class NodeKind {
    Destination,
    Listener,
    Gain,
    Oscillator,
    BiquadFilter,
    Compressor,
    Delay,
    BufferSource,
    Analyser,
    StereoPanner,
    Panner,
    WaveShaper,
    ConstantSource,
    Convolver,
    IIRFilter,
    ChannelSplitter,
    ChannelMerger,
    MediaStreamSource,
    MediaStreamDestination,
    WorkletBridge,
  };

  struct BiquadState {
    float x1 = 0.0f;
    float x2 = 0.0f;
    float y1 = 0.0f;
    float y2 = 0.0f;
  };

  struct Node {
    int32_t id = -1;
    NodeKind kind = NodeKind::Gain;
    int32_t inputCount = 1;
    int32_t outputCount = 1;
    std::unordered_map<std::string, float> paramValues;
    std::unordered_map<std::string, std::unique_ptr<ParamTimeline>> timelines;
    AudioBus current;
    AudioBus previous;
    uint64_t renderSerial = 0;

    int oscillatorType = 0;
    double phase = 0.0;
    double startTime = -1.0;
    double stopTime = 1.0e15;
    std::vector<float> periodicWave;

    int filterType = 0;
    std::vector<BiquadState> biquad;

    float compressorReduction = 0.0f;
    float compressorEnvelope = 0.0f;

    int panningModel = 1;
    int distanceModel = 1;
    float refDistance = 1.0f;
    float maxDistance = 10000.0f;
    float rolloffFactor = 1.0f;
    float coneInnerAngle = 360.0f;
    float coneOuterAngle = 360.0f;
    float coneOuterGain = 0.0f;

    float maxDelay = 1.0f;
    int delayWrite = 0;
    std::vector<std::vector<float>> delayLines;

    std::vector<float> sourceBuffer;
    int32_t sourceFrames = 0;
    int32_t sourceChannels = 0;
    int32_t sourceSampleRate = 44100;
    bool sourceLoop = false;
    double sourceStartTime = -1.0;
    double sourceStopTime = 1.0e15;
    double sourceCursor = 0.0;
    double sourceOffset = 0.0;
    double sourceDuration = 0.0;
    bool sourceHasDuration = false;
    double sourceLoopStart = 0.0;
    double sourceLoopEnd = 0.0;
    float sourceEnvelope = 1.0f;

    int analyserFftSize = 2048;
    float analyserMinDecibels = -100.0f;
    float analyserMaxDecibels = -30.0f;
    float analyserSmoothing = 0.8f;
    std::vector<float> analyserTime;
    std::vector<float> analyserPreviousDb;

    std::vector<float> waveShaperCurve;
    int waveShaperOversample = 0;

    std::vector<float> convolverBuffer;
    int32_t convolverFrames = 0;
    int32_t convolverChannels = 0;
    int32_t convolverSampleRate = 44100;
    bool convolverNormalize = true;
    std::vector<std::vector<float>> convolverHistory;
    int convolverWrite = 0;

    std::vector<double> iirFeedforward;
    std::vector<double> iirFeedback;
    std::vector<std::vector<float>> iirInputHistory;
    std::vector<std::vector<float>> iirOutputHistory;

    std::shared_ptr<WorkletBridgeState> bridge;
    std::vector<float> workletLastOutput;
    std::shared_ptr<std::atomic<bool>> machineActive;
    bool allowSilentInputSkip = false;
  };

  struct Connection {
    int32_t src = -1;
    int32_t dst = -1;
    int output = 0;
    int input = 0;
  };

  struct ParamConnection {
    int32_t src = -1;
    int32_t dst = -1;
    std::string param;
    int output = 0;
  };

private:
  int32_t addNode(Node node);
  Node *findNodeUnlocked(int32_t nodeId);
  const Node *findNodeUnlocked(int32_t nodeId) const;
  ParamTimeline &timelineFor(Node &node, const std::string &param);
  float currentParam(Node &node, const char *param, float fallback);
  void paramBlock(Node &node, const char *param, float fallback,
                  double blockStart, int frames, std::vector<int32_t> &stack,
                  std::vector<float> &values);
  void addParamInputBlock(Node &node, const char *param,
                          std::vector<int32_t> &stack,
                          std::vector<float> &values);

  AudioBus &renderNode(int32_t nodeId, std::vector<int32_t> &stack);
  void sumInputs(Node &node, std::vector<int32_t> &stack, AudioBus &input);
  void processNode(Node &node, const AudioBus &input,
                   std::vector<int32_t> &stack);
  void copyCurrentToPrevious();
  bool hasParamInputUnlocked(int32_t nodeId, const char *param) const;
  bool canSkipInactiveMachineNodeUnlocked(Node &node) const;
  bool canSkipSilentGainUnlocked(Node &node);

  void renderOscillator(Node &node, std::vector<int32_t> &stack);
  void renderConstantSource(Node &node, std::vector<int32_t> &stack);
  void renderBufferSource(Node &node, std::vector<int32_t> &stack);
  void renderBiquad(Node &node, const AudioBus &input,
                    std::vector<int32_t> &stack);
  void renderIIRFilter(Node &node, const AudioBus &input);
  void renderDelay(Node &node, const AudioBus &input,
                   std::vector<int32_t> &stack);
  void renderCompressor(Node &node, const AudioBus &input,
                        std::vector<int32_t> &stack);
  void renderStereoPanner(Node &node, const AudioBus &input,
                          std::vector<int32_t> &stack);
  void renderPanner(Node &node, const AudioBus &input,
                    std::vector<int32_t> &stack);
  void renderWaveShaper(Node &node, const AudioBus &input);
  void renderConvolver(Node &node, const AudioBus &input);
  void renderAnalyser(Node &node, const AudioBus &input);
  void renderMediaStreamSource(Node &node);
  void renderWorklet(Node &node, const AudioBus &input);

  bool pathExistsUnlocked(int32_t from, int32_t to) const;
  void markFeedbackIfCycleUnlocked(int32_t src, int32_t dst);

#if defined(WAJUCE_USE_RTAUDIO) && WAJUCE_USE_RTAUDIO
  bool ensureRealtimeStream();
  void closeRealtimeStream();
  static int rtAudioCallback(void *outputBuffer, void *inputBuffer,
                             unsigned int nFrames, double streamTime,
                             RtAudioStreamStatus status, void *userData);
  std::unique_ptr<RtAudio> realtime;
  bool realtimeOpen = false;
#endif

#if defined(WAJUCE_USE_APPLE_AUDIOUNIT) && WAJUCE_USE_APPLE_AUDIOUNIT
  bool ensureAppleAudioUnit();
  void closeAppleAudioUnit();
  static OSStatus appleAudioUnitCallback(void *inRefCon,
                                         AudioUnitRenderActionFlags *flags,
                                         const AudioTimeStamp *timeStamp,
                                         UInt32 busNumber, UInt32 frameCount,
                                         AudioBufferList *ioData);
  AudioComponentInstance appleAudioUnit = nullptr;
  bool appleAudioUnitOpen = false;
#endif

  mutable std::recursive_mutex graphMtx;
  mutable std::mutex machineVoiceActiveMtx;
  std::unordered_map<int32_t, Node> nodes;
  std::vector<Connection> connections;
  std::vector<ParamConnection> paramConnections;
  std::unordered_map<int32_t, std::vector<int32_t>> machineVoiceGroups;
  std::unordered_map<int32_t, int32_t> machineVoiceRootByNode;
  std::unordered_map<int32_t, std::shared_ptr<std::atomic<bool>>>
      machineVoiceActiveByNode;
  int32_t nextNodeId = 1;
  int32_t listenerNodeId = -1;
  uint64_t renderSerial = 0;
  int renderFrames = 0;
  int renderChannels = 2;
  double renderBlockStartTime = 0.0;
  std::vector<float> scratchParam;
  AudioBus realtimeInput;

  std::atomic<double> sampleRate{44100.0};
  std::atomic<int> bufferSize{512};
  std::atomic<int> inputChannels{2};
  std::atomic<int> outputChannels{2};
  std::atomic<int> preferredBitDepth{32};
  std::atomic<double> currentTime{0.0};
  std::atomic<int> state{0};
  std::atomic<int32_t> feedbackCycleCount{0};
  std::atomic<bool> mediaInputRequested{false};
  std::atomic<bool> appleInputPermissionPending{false};
};

extern std::unordered_map<int32_t, std::shared_ptr<Engine>> g_engines;
extern std::mutex g_engineMtx;
extern int32_t g_nextCtxId;
std::shared_ptr<Engine> findEngineForNode(int32_t nodeId);

} // namespace wajuce
