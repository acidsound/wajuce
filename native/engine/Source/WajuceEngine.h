#pragma once
/**
 * WajuceEngine.h — Main JUCE audio engine with AudioProcessorGraph.
 * Manages node lifecycle, graph connections, and audio device.
 */

#include "NodeRegistry.h"
#include "ParamAutomation.h"
#include "Processors.h"

#include <juce_audio_basics/juce_audio_basics.h>
#include <juce_audio_devices/juce_audio_devices.h>
#include <juce_audio_processors/juce_audio_processors.h>
#include <juce_core/juce_core.h>
#include <juce_events/juce_events.h>

#include <atomic>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>

namespace wajuce {

class Engine : public juce::AudioSource {
public:
  Engine(double sampleRate = 44100.0, int bufferSize = 512,
         int inputChannels = 2, int outputChannels = 2);
  ~Engine();

  // AudioSource
  void prepareToPlay(int samples, double sr) override;
  void releaseResources() override;
  void getNextAudioBlock(const juce::AudioSourceChannelInfo &info) override;

  // Lifecycle
  void resume();
  void suspend();
  void close();

  // State: 0=suspended, 1=running, 2=closed
  int getState() const { return state.load(); }
  double getCurrentTime() const { return currentTime.load(); }
  double getSampleRate() const { return sampleRate; }
  int32_t getDestinationId() const { return 0; } // destination is always ID 0

  // Node factory
  int32_t createGain();
  int32_t createOscillator();
  int32_t createBiquadFilter();
  int32_t createCompressor();
  int32_t createDelay(float maxDelay);
  int32_t createStereoPanner();
  int32_t createBufferSource();
  int32_t createAnalyser();
  int32_t createWaveShaper();
  int32_t createChannelSplitter(int32_t outputs);
  int32_t createChannelMerger(int32_t inputs);
  int32_t createMediaStreamSource();
  int32_t createMediaStreamDestination();
  int32_t createWorkletBridge(int32_t inputs, int32_t outputs);
  void createMachineVoice(int32_t *resultIds);
  void removeNode(int32_t nodeId);

  // Graph
  void connect(int32_t srcId, int32_t dstId, int output, int input);
  void disconnect(int32_t srcId, int32_t dstId);
  void disconnectAll(int32_t srcId);

  // Params
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

  // Oscillator control
  void oscSetType(int32_t nodeId, int type);
  void oscStart(int32_t nodeId, double when);
  void oscStop(int32_t nodeId, double when);
  void oscSetPeriodicWave(int32_t nodeId, const float *real, const float *imag,
                          int32_t len);

  // Filter control
  void filterSetType(int32_t nodeId, int type);

  // BufferSource control
  void bufferSourceSetBuffer(int32_t nodeId, const float *data, int32_t frames,
                             int32_t channels, int32_t sr);
  void bufferSourceStart(int32_t nodeId, double when);
  void bufferSourceStop(int32_t nodeId, double when);
  void bufferSourceSetLoop(int32_t nodeId, bool loop);

  // Analyser control
  void analyserSetFftSize(int32_t nodeId, int32_t size);
  void analyserGetByteFreqData(int32_t nodeId, uint8_t *data, int32_t len);
  void analyserGetByteTimeData(int32_t nodeId, uint8_t *data, int32_t len);
  void analyserGetFloatFreqData(int32_t nodeId, float *data, int32_t len);
  void analyserGetFloatTimeData(int32_t nodeId, float *data, int32_t len);

  // WaveShaper control
  void waveShaperSetCurve(int32_t nodeId, const float *data, int32_t len);
  void waveShaperSetOversample(int32_t nodeId, int type);

  NodeRegistry &getRegistry() { return registry; }

private:
  using NodeID = juce::AudioProcessorGraph::NodeID;

  // Add a processor to the graph and registry
  int32_t addToGraph(NodeType type, std::unique_ptr<juce::AudioProcessor> proc);

  juce::AudioDeviceManager deviceManager;
  juce::AudioSourcePlayer sourcePlayer;
  std::unique_ptr<juce::AudioProcessorGraph> graph;
  juce::AudioProcessorGraph::Node::Ptr inputNode;
  juce::AudioProcessorGraph::Node::Ptr outputNode;

  NodeRegistry registry;
  // Map from our IDs to graph NodeIDs
  std::unordered_map<int32_t, NodeID> idToGraphNode;
  std::mutex graphMtx;

  void processAutomation(double startTime, double sampleRate, int numSamples);

  struct FeedbackConnection {
    int32_t srcId;
    int32_t dstId;
    int output;
    int input;
    NodeID sender;
    NodeID receiver;
    std::shared_ptr<juce::AudioBuffer<float>> buffer;
  };
  std::vector<FeedbackConnection> feedbackConnections;

  double sampleRate;
  int bufferSize;
  std::atomic<double> currentTime{0.0};
  std::atomic<int> state{0}; // 0=suspended
  int64_t totalSamplesProcessed = 0;
};

extern std::unordered_map<int32_t, std::unique_ptr<Engine>> g_engines;
extern std::mutex g_engineMtx;
extern int32_t g_nextCtxId;

Engine *findEngineForNode(int32_t nodeId);

} // namespace wajuce
