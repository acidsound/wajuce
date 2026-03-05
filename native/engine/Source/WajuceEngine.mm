/**
 * WajuceEngine.cpp — Implementation of the JUCE audio engine.
 */

#include "WajuceEngine.h"
#include <cassert>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <juce_audio_devices/juce_audio_devices.h>
#include <juce_audio_formats/juce_audio_formats.h>
#ifdef JUCE_IOS
#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#define WA_LOG(fmt, ...) fprintf(stderr, fmt "\n", ##__VA_ARGS__)
#else
#define WA_LOG(fmt, ...) fprintf(stderr, fmt "\n", ##__VA_ARGS__)
#endif

#include "../../../src/wajuce.h"

namespace wajuce {

using NodeID = juce::AudioProcessorGraph::NodeID;

// ---- Globals ----
wajuce_midi_callback_t g_midiGlobalCallback = nullptr;

// MIDI Proxy Definition
struct MidiInputProxy : public juce::MidiInputCallback {
  int32_t index;
  std::unique_ptr<juce::MidiInput> input;

  MidiInputProxy(int32_t idx, std::unique_ptr<juce::MidiInput> in)
      : index(idx), input(std::move(in)) {}

  void handleIncomingMidiMessage(juce::MidiInput *source,
                                 const juce::MidiMessage &message) override {
    if (g_midiGlobalCallback) {
      g_midiGlobalCallback(index, message.getRawData(),
                           (int32_t)message.getRawDataSize(),
                           message.getTimeStamp());
    }
  }
};

std::unordered_map<int32_t, std::shared_ptr<Engine>> g_engines;
std::mutex g_engineMtx;
int32_t g_nextCtxId = 1;

std::unordered_map<int32_t, std::unique_ptr<MidiInputProxy>> g_midiInputs;
std::unordered_map<int32_t, std::unique_ptr<juce::MidiOutput>> g_midiOutputs;
std::mutex g_midiMtx;

template <typename Fn>
auto runOnJuceMessageThreadSync(Fn &&fn) -> decltype(fn()) {
  auto *messageManager = juce::MessageManager::getInstance();
  if (!messageManager->isThisTheMessageThread()) {
    messageManager->setCurrentThreadAsMessageThread();
  }
  return fn();
}

std::shared_ptr<Engine> findEngineForNode(int32_t nodeId) {
  std::lock_guard<std::mutex> lock(g_engineMtx);
  for (auto &[id, engine] : g_engines) {
    if (engine->getRegistry().contains(nodeId))
      return engine;
  }
  return {};
}

static std::shared_ptr<wajuce::Engine> getEngine(int32_t id) {
  std::lock_guard<std::mutex> lock(wajuce::g_engineMtx);
  auto it = wajuce::g_engines.find(id);
  return it != wajuce::g_engines.end() ? it->second : nullptr;
}

static std::shared_ptr<wajuce::WorkletBridgeState>
getWorkletBridgeState(int32_t ctxId, int32_t bridgeId) {
  auto engine = getEngine(ctxId);
  if (!engine)
    return nullptr;

  auto state = engine->getWorkletBridgeState(bridgeId);
  if (!state || !state->active.load(std::memory_order_relaxed))
    return nullptr;
  return state;
}

static wajuce::SPSCRingBuffer *getWorkletRingBuffer(int32_t ctxId,
                                                    int32_t bridgeId,
                                                    int32_t direction,
                                                    int32_t channel) {
  auto state = getWorkletBridgeState(ctxId, bridgeId);
  if (!state)
    return nullptr;

  auto buffers = (direction == 0) ? state->toIsolate : state->fromIsolate;
  if (!buffers)
    return nullptr;
  return buffers->getChannel(channel);
}

// ============================================================================
// Engine Implementation
// ============================================================================

Engine::Engine(double sr, int bs, int inCh, int outCh)
    : sampleRate(sr), bufferSize(bs) {
  WA_LOG("[wajuce] Engine::Engine sr=%f, bs=%d, in=%d, out=%d", sr, bs, inCh,
         outCh);
  int effectiveInCh = juce::jmax(0, inCh);
  int effectiveOutCh = juce::jmax(1, outCh);
  graph = std::make_unique<juce::AudioProcessorGraph>();

  inputNode = graph->addNode(
      std::make_unique<juce::AudioProcessorGraph::AudioGraphIOProcessor>(
          juce::AudioProcessorGraph::AudioGraphIOProcessor::audioInputNode));
  outputNode = graph->addNode(
      std::make_unique<juce::AudioProcessorGraph::AudioGraphIOProcessor>(
          juce::AudioProcessorGraph::AudioGraphIOProcessor::audioOutputNode));

#ifdef JUCE_IOS
  // Prefer playback-only unless input is explicitly requested and available.
  auto session = [AVAudioSession sharedInstance];
  NSError *error = nil;
  if (effectiveInCh > 0 &&
      [session recordPermission] == AVAudioSessionRecordPermissionDenied) {
    WA_LOG("[wajuce] microphone permission denied, falling back to output-only audio session");
    effectiveInCh = 0;
  }

  NSString *category =
      (effectiveInCh > 0) ? AVAudioSessionCategoryPlayAndRecord
                          : AVAudioSessionCategoryPlayback;
  AVAudioSessionCategoryOptions options = AVAudioSessionCategoryOptionMixWithOthers;
  if (effectiveInCh > 0) {
    options |= AVAudioSessionCategoryOptionDefaultToSpeaker |
               AVAudioSessionCategoryOptionAllowBluetooth;
  }

  [session setCategory:category withOptions:options error:&error];
  if (error) {
    WA_LOG("[wajuce] AVAudioSession error: %s",
           [[error localizedDescription] UTF8String]);
  }
  [session setActive:YES error:nil];
#endif

  graph->setPlayConfigDetails(effectiveInCh, effectiveOutCh, sr, bs);
  graph->prepareToPlay(sr, bs);

  auto err =
      deviceManager.initialiseWithDefaultDevices(effectiveInCh, effectiveOutCh);
  if (err.isNotEmpty()) {
    WA_LOG("[wajuce] initialiseWithDefaultDevices error: %s", err.toRawUTF8());
  }

  if (auto *device = deviceManager.getCurrentAudioDevice()) {
    const auto deviceSampleRate = device->getCurrentSampleRate();
    const auto deviceBufferSize = device->getCurrentBufferSizeSamples();
    if (deviceSampleRate > 0.0) {
      sampleRate.store(deviceSampleRate, std::memory_order_relaxed);
    }
    if (deviceBufferSize > 0) {
      bufferSize.store(deviceBufferSize, std::memory_order_relaxed);
    }
  }

  const double currentSampleRate = sampleRate.load(std::memory_order_relaxed);
  const int currentBufferSize = bufferSize.load(std::memory_order_relaxed);
  graph->setPlayConfigDetails(effectiveInCh, effectiveOutCh, currentSampleRate,
                              currentBufferSize);
  graph->prepareToPlay(currentSampleRate, currentBufferSize);
  sampleRateHoldValues.assign((size_t)juce::jmax(1, effectiveOutCh), 0.0f);
  sampleRateHoldPhase = 0.0;

  deviceManager.addAudioCallback(&sourcePlayer);
  sourcePlayer.setSource(this);
  refreshAudioDeviceFormatCache();
  debugLastXRunCount = deviceManager.getXRunCount();
  // Keep native device rate by default. Software downsample is opt-in only via
  // explicit low-rate preference.
  preferredRenderSampleRate.store(0.0, std::memory_order_relaxed);
  preferredRenderBitDepth.store(32, std::memory_order_relaxed);
}

Engine::~Engine() {
  sourcePlayer.setSource(nullptr);
  deviceManager.removeAudioCallback(&sourcePlayer);
  graph.reset();
}

void Engine::prepareToPlay(int samples, double sr) {
  WA_LOG("[wajuce] Engine::prepareToPlay sr=%f, bs=%d", sr, samples);
  sampleRate.store(sr, std::memory_order_relaxed);
  bufferSize.store(samples, std::memory_order_relaxed);
  debugLastBlockSize = samples;
  debugLastCallbackMs = 0.0;
  debugFramesSinceLastHealthLog = 0;
  int inCh = graph->getMainBusNumInputChannels();
  int outCh = graph->getMainBusNumOutputChannels();
  graph->setPlayConfigDetails(inCh, outCh, sr, samples);
  graph->prepareToPlay(sr, samples);
  sampleRateHoldValues.assign((size_t)juce::jmax(1, outCh), 0.0f);
  sampleRateHoldPhase = 0.0;
  refreshAudioDeviceFormatCache();
}

void Engine::releaseResources() { graph->releaseResources(); }

void Engine::getNextAudioBlock(const juce::AudioSourceChannelInfo &info) {
  if (state.load() != 1) {
    info.clearActiveBufferRegion();
    return;
  }

  const double callbackStartMs = juce::Time::getMillisecondCounterHiRes();
  logAudioHealthIfNeeded(info.numSamples);
  double now = currentTime.load(std::memory_order_relaxed);
  const double currentSampleRate = sampleRate.load(std::memory_order_relaxed);
  processAutomation(now, currentSampleRate, info.numSamples);

  // Use sub-buffer to respect startSample and numSamples
  juce::AudioBuffer<float> proxy(info.buffer->getArrayOfWritePointers(),
                                 info.buffer->getNumChannels(),
                                 info.startSample, info.numSamples);
  // proxy.clear(); // DO NOT CLEAR - We need physical input from info.buffer
  juce::MidiBuffer midi;
  graph->processBlock(proxy, midi);
  applyLoFiPostProcess(proxy);

  if (currentSampleRate > 0.0 && info.numSamples > 0) {
    const double budgetMs =
        (1000.0 * (double)info.numSamples) / currentSampleRate;
    const double usedMs =
        juce::Time::getMillisecondCounterHiRes() - callbackStartMs;
    if (budgetMs > 0.0 && usedMs > (budgetMs * 0.85)) {
      const double nowMs = juce::Time::getMillisecondCounterHiRes();
      if (debugLastBudgetLogMs <= 0.0 ||
          (nowMs - debugLastBudgetLogMs) >= 1000.0) {
        WA_LOG("[wajuce] Audio callback budget: used=%0.2fms budget=%0.2fms block=%d sr=%0.1f",
               usedMs, budgetMs, info.numSamples, currentSampleRate);
        debugLastBudgetLogMs = nowMs;
      }
    }
  }

  totalSamplesProcessed += info.numSamples;
  currentTime.store((double)totalSamplesProcessed / currentSampleRate,
                    std::memory_order_relaxed);
}

void Engine::refreshAudioDeviceFormatCache() {
  if (auto *device = deviceManager.getCurrentAudioDevice()) {
    const auto deviceSr = device->getCurrentSampleRate();
    const auto deviceBs = device->getCurrentBufferSizeSamples();
    if (deviceSr > 0.0) {
      debugCachedDeviceSampleRate = deviceSr;
    }
    if (deviceBs > 0) {
      debugCachedDeviceBufferSize = deviceBs;
    }
  }
}

void Engine::logAudioHealthIfNeeded(int numSamples) {
  if (numSamples <= 0) {
    return;
  }

  ++debugBlocksProcessed;
  debugFramesSinceLastHealthLog += numSamples;

  if (debugLastBlockSize > 0 && numSamples != debugLastBlockSize) {
    WA_LOG("[wajuce] Audio callback block-size changed: prev=%d now=%d",
           debugLastBlockSize, numSamples);
  }
  debugLastBlockSize = numSamples;

  const double nowMs = juce::Time::getMillisecondCounterHiRes();
  const double currentSampleRate = sampleRate.load(std::memory_order_relaxed);

  if (debugLastCallbackMs > 0.0 && currentSampleRate > 0.0) {
    const double expectedMs = (1000.0 * (double)numSamples) / currentSampleRate;
    const double actualMs = nowMs - debugLastCallbackMs;
    if (actualMs > expectedMs * 1.75) {
      WA_LOG("[wajuce] Audio callback jitter: actual=%0.2fms expected=%0.2fms block=%d",
             actualMs, expectedMs, numSamples);
    }
  }
  debugLastCallbackMs = nowMs;

  const int currentXrunCount = deviceManager.getXRunCount();
  if (debugLastXRunCount < 0) {
    debugLastXRunCount = currentXrunCount;
  }
  if (currentXrunCount > debugLastXRunCount) {
    WA_LOG("[wajuce] XRUN increment: delta=%d total=%d block=%d sr=%0.1f",
           currentXrunCount - debugLastXRunCount, currentXrunCount, numSamples,
           currentSampleRate);
    debugLastXRunCount = currentXrunCount;
  }

  bool formatChanged = false;
  if (auto *device = deviceManager.getCurrentAudioDevice()) {
    const auto deviceSr = device->getCurrentSampleRate();
    const auto deviceBs = device->getCurrentBufferSizeSamples();

    if (debugCachedDeviceSampleRate <= 0.0 && deviceSr > 0.0) {
      debugCachedDeviceSampleRate = deviceSr;
    }
    if (debugCachedDeviceBufferSize <= 0 && deviceBs > 0) {
      debugCachedDeviceBufferSize = deviceBs;
    }

    const bool srChanged =
        deviceSr > 0.0 &&
        std::abs(deviceSr - debugCachedDeviceSampleRate) > 0.5;
    const bool bsChanged = deviceBs > 0 && deviceBs != debugCachedDeviceBufferSize;
    if (srChanged || bsChanged) {
      WA_LOG("[wajuce] Device format changed: sr=%0.1f->%0.1f bs=%d->%d",
             debugCachedDeviceSampleRate, deviceSr, debugCachedDeviceBufferSize,
             deviceBs);
      debugCachedDeviceSampleRate = deviceSr;
      debugCachedDeviceBufferSize = deviceBs;
      formatChanged = true;
    }
  }

  const bool periodicLogDue =
      currentSampleRate > 0.0 &&
      debugFramesSinceLastHealthLog >= static_cast<int64_t>(currentSampleRate);

  if (periodicLogDue || formatChanged) {
    if (periodicLogDue) {
      debugFramesSinceLastHealthLog = 0;
    }
    WA_LOG("[wajuce] AudioHealth xrun=%d callbackFrames=%d graphSR=%0.1f deviceSR=%0.1f deviceBS=%d",
           currentXrunCount, numSamples, currentSampleRate,
           debugCachedDeviceSampleRate, debugCachedDeviceBufferSize);
  }
}

void Engine::resume() { state = 1; }
void Engine::suspend() { state = 0; }
void Engine::close() {
  state = 2;
  sourcePlayer.setSource(nullptr);
  deviceManager.removeAudioCallback(&sourcePlayer);
}

int Engine::getCurrentBitDepth() const {
  auto *device = deviceManager.getCurrentAudioDevice();
  if (device == nullptr)
    return 32;
  const int bitDepth = device->getCurrentBitDepth();
  return bitDepth > 0 ? bitDepth : 32;
}

bool Engine::setPreferredSampleRate(double preferredSampleRate) {
  if (preferredSampleRate <= 0.0) {
    return false;
  }

  // Reset software downsample unless we explicitly decide to enable it below.
  preferredRenderSampleRate.store(0.0, std::memory_order_relaxed);
  const bool restartAudio = state.load(std::memory_order_relaxed) != 2;
  if (restartAudio) {
    sourcePlayer.setSource(nullptr);
    deviceManager.removeAudioCallback(&sourcePlayer);
  }

  juce::AudioDeviceManager::AudioDeviceSetup setup;
  deviceManager.getAudioDeviceSetup(setup);

  if (std::abs(setup.sampleRate - preferredSampleRate) > 0.5) {
    setup.sampleRate = preferredSampleRate;
    const auto err = deviceManager.setAudioDeviceSetup(setup, true);
    if (err.isNotEmpty()) {
      WA_LOG("[wajuce] device sample-rate switch failed, keeping device rate: %s",
             err.toRawUTF8());
    }
  }

  if (auto *device = deviceManager.getCurrentAudioDevice()) {
    const auto deviceSampleRate = device->getCurrentSampleRate();
    const auto deviceBufferSize = device->getCurrentBufferSizeSamples();
    if (deviceSampleRate > 0.0) {
      sampleRate.store(deviceSampleRate, std::memory_order_relaxed);
    }
    if (deviceBufferSize > 0) {
      bufferSize.store(deviceBufferSize, std::memory_order_relaxed);
    }
  }

  {
    std::lock_guard<std::mutex> lock(graphMtx);
    const int inCh = graph->getMainBusNumInputChannels();
    const int outCh = graph->getMainBusNumOutputChannels();
    const double currentSampleRate = sampleRate.load(std::memory_order_relaxed);
    const int currentBufferSize = bufferSize.load(std::memory_order_relaxed);
    graph->setPlayConfigDetails(inCh, outCh, currentSampleRate,
                                currentBufferSize);
    graph->prepareToPlay(currentSampleRate, currentBufferSize);
    sampleRateHoldValues.assign((size_t)juce::jmax(1, outCh), 0.0f);
    sampleRateHoldPhase = 0.0;
  }

  if (restartAudio) {
    deviceManager.addAudioCallback(&sourcePlayer);
    sourcePlayer.setSource(this);
  }

  refreshAudioDeviceFormatCache();
  const double currentSampleRate = sampleRate.load(std::memory_order_relaxed);
  bool accepted = std::abs(currentSampleRate - preferredSampleRate) <= 1.0;
  if (!accepted) {
    // Near-native mismatch (e.g. 48k device vs 44.1k request on iOS) should
    // run at device rate to avoid coarse sample-hold artifacts.
    constexpr double kLoFiReductionRatioThreshold = 0.8;
    const double ratio = (currentSampleRate > 0.0)
                             ? (preferredSampleRate / currentSampleRate)
                             : 1.0;

    if (ratio > 0.0 && ratio <= kLoFiReductionRatioThreshold) {
      preferredRenderSampleRate.store(preferredSampleRate,
                                      std::memory_order_relaxed);
      WA_LOG("[wajuce] enabling software lo-fi downsample: device=%0.1f, target=%0.1f",
             currentSampleRate, preferredSampleRate);
      accepted = true;
    } else {
      WA_LOG("[wajuce] preferred sample-rate unavailable; using device rate: device=%0.1f, requested=%0.1f",
             currentSampleRate, preferredSampleRate);
    }
  }

  return accepted;
}

void Engine::applyLoFiPostProcess(juce::AudioBuffer<float> &buffer) {
  const int channels = buffer.getNumChannels();
  const int frames = buffer.getNumSamples();
  if (channels <= 0 || frames <= 0) {
    return;
  }

  const double deviceRate = sampleRate.load(std::memory_order_relaxed);
  const double targetRate =
      preferredRenderSampleRate.load(std::memory_order_relaxed);
  const bool shouldReduceRate =
      targetRate > 0.0 && deviceRate > 0.0 && targetRate < (deviceRate - 1.0);

  if (shouldReduceRate &&
      (int)sampleRateHoldValues.size() >= channels) {
    const double holdLength = juce::jmax(1.0, deviceRate / targetRate);
    for (int i = 0; i < frames; ++i) {
      if (sampleRateHoldPhase <= 0.0) {
        for (int ch = 0; ch < channels; ++ch) {
          sampleRateHoldValues[(size_t)ch] = buffer.getSample(ch, i);
        }
        sampleRateHoldPhase += holdLength;
      }
      for (int ch = 0; ch < channels; ++ch) {
        buffer.setSample(ch, i, sampleRateHoldValues[(size_t)ch]);
      }
      sampleRateHoldPhase -= 1.0;
    }
  } else {
    sampleRateHoldPhase = 0.0;
  }

  int bitDepth = preferredRenderBitDepth.load(std::memory_order_relaxed);
  bitDepth = juce::jlimit(2, 32, bitDepth);
  if (bitDepth >= 32) {
    return;
  }

  const double maxInt = std::pow(2.0, bitDepth - 1) - 1.0;
  if (maxInt <= 0.0) {
    return;
  }

  for (int ch = 0; ch < channels; ++ch) {
    float *data = buffer.getWritePointer(ch);
    for (int i = 0; i < frames; ++i) {
      const float clamped = juce::jlimit(-1.0f, 1.0f, data[i]);
      data[i] = (float)(std::round((double)clamped * maxInt) / maxInt);
    }
  }
}

bool Engine::setPreferredBitDepth(int preferredBitDepth) {
  if (preferredBitDepth < 2 || preferredBitDepth > 32) {
    return false;
  }

  preferredRenderBitDepth.store(preferredBitDepth, std::memory_order_relaxed);
  return true;
}

// ============================================================================
// Node Factory
// ============================================================================

int32_t Engine::addToGraph(NodeType type,
                           std::unique_ptr<juce::AudioProcessor> proc) {
  std::lock_guard<std::mutex> lock(graphMtx);
  constexpr auto updateKind = juce::AudioProcessorGraph::UpdateKind::async;
  const double currentSampleRate = sampleRate.load(std::memory_order_relaxed);
  const int currentBufferSize = bufferSize.load(std::memory_order_relaxed);
  proc->setPlayConfigDetails(2, 2, currentSampleRate, currentBufferSize);
  proc->prepareToPlay(currentSampleRate, currentBufferSize);

  // Set engine time pointer for scheduled nodes
  if (type == NodeType::Oscillator) {
    static_cast<OscillatorProcessor *>(proc.get())->engineTimePtr =
        &currentTime;
  } else if (type == NodeType::BufferSource) {
    static_cast<BufferSourceProcessor *>(proc.get())->engineTimePtr =
        &currentTime;
  } else if (type == NodeType::Delay) {
    auto *delay = static_cast<DelayProcessor *>(proc.get());
    // Note: ID will be set after registry.add below
  }

  auto *rawPtr = proc.get();
  auto node = graph->addNode(std::move(proc), std::nullopt, updateKind);
  if (!node)
    return -1;

  int32_t id = registry.add(type, rawPtr);
  idToGraphNode[id] = node->nodeID;
  return id;
}

int32_t Engine::createGain() {
  return addToGraph(NodeType::Gain, std::make_unique<GainProcessor>());
}
int32_t Engine::createOscillator() {
  return addToGraph(NodeType::Oscillator,
                    std::make_unique<OscillatorProcessor>());
}
int32_t Engine::createBiquadFilter() {
  return addToGraph(NodeType::BiquadFilter,
                    std::make_unique<BiquadFilterProcessor>());
}
int32_t Engine::createCompressor() {
  return addToGraph(NodeType::Compressor,
                    std::make_unique<CompressorProcessor>());
}
int32_t Engine::createDelay(float d) {
  return addToGraph(NodeType::Delay, std::make_unique<DelayProcessor>(d));
}
int32_t Engine::createStereoPanner() {
  return addToGraph(NodeType::StereoPanner,
                    std::make_unique<StereoPannerProcessor>());
}
int32_t Engine::createBufferSource() {
  return addToGraph(NodeType::BufferSource,
                    std::make_unique<BufferSourceProcessor>());
}
int32_t Engine::createAnalyser() {
  return addToGraph(NodeType::Analyser, std::make_unique<AnalyserProcessor>());
}
int32_t Engine::createWaveShaper() {
  return addToGraph(NodeType::WaveShaper,
                    std::make_unique<WaveShaperProcessor>());
}
int32_t Engine::createChannelSplitter(int32_t outputs) {
  return addToGraph(NodeType::ChannelSplitter,
                    std::make_unique<ChannelSplitterProcessor>(outputs));
}
int32_t Engine::createChannelMerger(int32_t inputs) {
  return addToGraph(NodeType::ChannelMerger,
                    std::make_unique<ChannelMergerProcessor>(inputs));
}
int32_t Engine::createMediaStreamSource() {
  auto id = addToGraph(NodeType::MediaStreamSource,
                       std::make_unique<MediaStreamSourceProcessor>());
  if (id != -1) {
    std::lock_guard<std::mutex> lock(graphMtx);
    constexpr auto updateKind = juce::AudioProcessorGraph::UpdateKind::async;
    auto it = idToGraphNode.find(id);
    if (it != idToGraphNode.end()) {
      graph->addConnection({{inputNode->nodeID, 0}, {it->second, 0}},
                           updateKind);
      graph->addConnection({{inputNode->nodeID, 1}, {it->second, 1}},
                           updateKind);
    }
  }
  return id;
}
int32_t Engine::createMediaStreamDestination() {
  return addToGraph(NodeType::MediaStreamDestination,
                    std::make_unique<MediaStreamDestinationProcessor>());
}

int32_t Engine::createWorkletBridge(int32_t inputs, int32_t outputs) {
  auto bridge = std::make_unique<WorkletBridgeProcessor>(inputs, outputs);
  auto sharedState = bridge->getSharedState();
  const int32_t nodeId = addToGraph(NodeType::WorkletBridge, std::move(bridge));
  if (nodeId != -1 && sharedState) {
    std::lock_guard<std::mutex> lock(graphMtx);
    workletBridgeStates[nodeId] = std::move(sharedState);
  }
  return nodeId;
}

int32_t Engine::getLiveNodeCount() {
  std::lock_guard<std::mutex> lock(graphMtx);
  return static_cast<int32_t>(idToGraphNode.size());
}

int32_t Engine::getFeedbackBridgeCount() {
  std::lock_guard<std::mutex> lock(graphMtx);
  return static_cast<int32_t>(feedbackConnections.size());
}

int32_t Engine::getMachineVoiceGroupCount() {
  std::lock_guard<std::mutex> lock(graphMtx);
  return static_cast<int32_t>(machineVoiceGroups.size());
}

std::shared_ptr<WorkletBridgeState> Engine::getWorkletBridgeState(
    int32_t nodeId) {
  std::lock_guard<std::mutex> lock(graphMtx);
  auto it = workletBridgeStates.find(nodeId);
  return it != workletBridgeStates.end() ? it->second : nullptr;
}

int32_t Engine::getWorkletBridgeInputChannelCount(int32_t nodeId) {
  auto state = getWorkletBridgeState(nodeId);
  return state ? state->numInputs : 0;
}

int32_t Engine::getWorkletBridgeOutputChannelCount(int32_t nodeId) {
  auto state = getWorkletBridgeState(nodeId);
  return state ? state->numOutputs : 0;
}

int32_t Engine::getWorkletBridgeCapacity(int32_t nodeId) {
  auto state = getWorkletBridgeState(nodeId);
  if (!state || !state->toIsolate)
    return 0;
  auto *channel = state->toIsolate->getChannel(0);
  return channel ? channel->getCapacity() : 0;
}

void Engine::releaseWorkletBridge(int32_t nodeId) {
  std::lock_guard<std::mutex> lock(graphMtx);
  auto it = workletBridgeStates.find(nodeId);
  if (it == workletBridgeStates.end() || !it->second) {
    return;
  }

  const auto dropped = it->second->droppedInputSamples.load(
      std::memory_order_relaxed);
  const auto underruns = it->second->outputUnderrunSamples.load(
      std::memory_order_relaxed);
  if (dropped > 0 || underruns > 0) {
    WA_LOG("[wajuce] WorkletBridge stats bridge=%d droppedIn=%lld underrunOut=%lld",
           nodeId, (long long)dropped, (long long)underruns);
  }

  workletBridgeStates.erase(it);
}

void Engine::removeNodeInternal(
    int32_t nodeId, juce::AudioProcessorGraph::UpdateKind updateKind) {
  std::lock_guard<std::recursive_mutex> registryLock(registry.getMutex());
  if (auto stateIt = workletBridgeStates.find(nodeId);
      stateIt != workletBridgeStates.end() && stateIt->second) {
    stateIt->second->active.store(false, std::memory_order_relaxed);
    if (stateIt->second->toIsolate) {
      stateIt->second->toIsolate->clear();
    }
    if (stateIt->second->fromIsolate) {
      stateIt->second->fromIsolate->clear();
    }
  }
  registry.remove(nodeId);
  machineVoiceRootByNode.erase(nodeId);

  auto nodeIt = idToGraphNode.find(nodeId);
  if (nodeIt != idToGraphNode.end()) {
    graph->removeNode(nodeIt->second, updateKind);
    idToGraphNode.erase(nodeIt);
  }

  for (auto fit = feedbackConnections.begin();
       fit != feedbackConnections.end();) {
    if (fit->srcId == nodeId || fit->dstId == nodeId) {
      graph->removeNode(fit->sender, updateKind);
      graph->removeNode(fit->receiver, updateKind);
      fit = feedbackConnections.erase(fit);
    } else {
      ++fit;
    }
  }
}

void Engine::removeNode(int32_t nodeId) {
  std::lock_guard<std::mutex> lock(graphMtx);
  constexpr auto updateKind = juce::AudioProcessorGraph::UpdateKind::async;

  auto rootIt = machineVoiceRootByNode.find(nodeId);
  if (rootIt != machineVoiceRootByNode.end()) {
    const int32_t rootId = rootIt->second;
    auto groupIt = machineVoiceGroups.find(rootId);
    if (groupIt != machineVoiceGroups.end()) {
      const auto members = groupIt->second;
      machineVoiceGroups.erase(groupIt);
      for (const auto memberId : members) {
        machineVoiceRootByNode.erase(memberId);
      }
      for (const auto memberId : members) {
        removeNodeInternal(memberId, updateKind);
      }
      return;
    }
    machineVoiceRootByNode.erase(rootIt);
  }

  removeNodeInternal(nodeId, updateKind);
}

// Batch creation for Machine Voice
void Engine::createMachineVoice(int32_t *resultIds) {
  std::lock_guard<std::mutex> lock(graphMtx);
  constexpr auto updateKind = juce::AudioProcessorGraph::UpdateKind::async;

  // Create Nodes
  // 0: Osc, 1: Filter, 2: Gain, 3: Panner, 4: Delay, 5: DelayFb, 6: DelayWet
  auto osc = std::make_unique<OscillatorProcessor>();
  auto filter = std::make_unique<BiquadFilterProcessor>();
  auto gain = std::make_unique<GainProcessor>();
  auto panner = std::make_unique<StereoPannerProcessor>();
  auto delay = std::make_unique<DelayProcessor>();
  auto delayFb = std::make_unique<GainProcessor>();
  auto delayWet = std::make_unique<GainProcessor>();

  // Configuration & Preparation (Minimal for batch, graph will handle rest)
  const double sr = sampleRate.load(std::memory_order_relaxed);
  const int bs = bufferSize.load(std::memory_order_relaxed);

  // Set basic layout to 2 channels (Stereo) to avoid massive overhead of 32
  osc->setPlayConfigDetails(0, 2, sr, bs);
  osc->engineTimePtr = &currentTime;
  osc->startTime = 0.0;

  filter->setPlayConfigDetails(2, 2, sr, bs);
  gain->setPlayConfigDetails(2, 2, sr, bs);
  panner->setPlayConfigDetails(2, 2, sr, bs);
  delay->setPlayConfigDetails(2, 2, sr, bs);
  delayFb->setPlayConfigDetails(2, 2, sr, bs);
  delayWet->setPlayConfigDetails(2, 2, sr, bs);

  // Initial Params
  gain->gain = 0.0f;
  // Web Audio DelayNode default delayTime is 0 seconds.
  delay->delayTime = 0.0f;
  delayFb->gain = 0.0f;
  delayWet->gain = 0.0f;

  // Add to Graph
  auto nOsc = graph->addNode(std::move(osc), std::nullopt, updateKind);
  auto nFilter = graph->addNode(std::move(filter), std::nullopt, updateKind);
  auto nGain = graph->addNode(std::move(gain), std::nullopt, updateKind);
  auto nPanner = graph->addNode(std::move(panner), std::nullopt, updateKind);
  auto nDelay = graph->addNode(std::move(delay), std::nullopt, updateKind);
  auto nDelayFb = graph->addNode(std::move(delayFb), std::nullopt, updateKind);
  auto nDelayWet =
      graph->addNode(std::move(delayWet), std::nullopt, updateKind);

  // INTERNAL Connections (No output connection yet - Lazy)
  // Osc (mono) -> Filter -> Gain -> Panner (stereo)
  // Duplicate mono signal to ch0/ch1 before panner so center pan is true stereo.
  graph->addConnection({{nOsc->nodeID, 0}, {nFilter->nodeID, 0}}, updateKind);
  graph->addConnection({{nOsc->nodeID, 0}, {nFilter->nodeID, 1}}, updateKind);
  graph->addConnection({{nFilter->nodeID, 0}, {nGain->nodeID, 0}}, updateKind);
  graph->addConnection({{nFilter->nodeID, 1}, {nGain->nodeID, 1}}, updateKind);
  graph->addConnection({{nGain->nodeID, 0}, {nPanner->nodeID, 0}}, updateKind);
  graph->addConnection({{nGain->nodeID, 1}, {nPanner->nodeID, 1}}, updateKind);

  // Gain -> Delay path (stereo)
  graph->addConnection({{nGain->nodeID, 0}, {nDelay->nodeID, 0}}, updateKind);
  graph->addConnection({{nGain->nodeID, 1}, {nDelay->nodeID, 1}}, updateKind);
  graph->addConnection({{nDelay->nodeID, 0}, {nDelayWet->nodeID, 0}},
                       updateKind);
  graph->addConnection({{nDelay->nodeID, 1}, {nDelayWet->nodeID, 1}},
                       updateKind);

  // Delay Feedback loop (stereo)
  graph->addConnection({{nDelay->nodeID, 0}, {nDelayFb->nodeID, 0}},
                       updateKind);
  graph->addConnection({{nDelay->nodeID, 1}, {nDelayFb->nodeID, 1}},
                       updateKind);

  // Complete external feedback path with a 1-block bridge.
  // This preserves web-style Delay->Gain->Delay behavior while avoiding
  // direct graph cycles in JUCE.
  std::shared_ptr<juce::AudioBuffer<float>> feedbackSharedBuffer;
  juce::AudioProcessorGraph::NodeID feedbackSenderNodeId{};
  juce::AudioProcessorGraph::NodeID feedbackReceiverNodeId{};
  bool feedbackBridgeReady = false;

  feedbackSharedBuffer =
      std::make_shared<juce::AudioBuffer<float>>(2, bs);
  feedbackSharedBuffer->clear();

  auto feedbackSender =
      std::make_unique<FeedbackSenderProcessor>(feedbackSharedBuffer);
  feedbackSender->setPlayConfigDetails(2, 2, sr, bs);
  feedbackSender->prepareToPlay(sr, bs);
  auto feedbackReceiver =
      std::make_unique<FeedbackReceiverProcessor>(feedbackSharedBuffer);
  feedbackReceiver->setPlayConfigDetails(2, 2, sr, bs);
  feedbackReceiver->prepareToPlay(sr, bs);

  auto nFeedbackSender =
      graph->addNode(std::move(feedbackSender), std::nullopt, updateKind);
  auto nFeedbackReceiver =
      graph->addNode(std::move(feedbackReceiver), std::nullopt, updateKind);

  if (nFeedbackSender && nFeedbackReceiver) {
    feedbackSenderNodeId = nFeedbackSender->nodeID;
    feedbackReceiverNodeId = nFeedbackReceiver->nodeID;

    bool c0 = graph->addConnection(
        {{nDelayFb->nodeID, 0}, {feedbackSenderNodeId, 0}}, updateKind);
    bool c1 = graph->addConnection(
        {{nDelayFb->nodeID, 1}, {feedbackSenderNodeId, 1}}, updateKind);
    bool c2 = graph->addConnection(
        {{feedbackReceiverNodeId, 0}, {nDelay->nodeID, 0}}, updateKind);
    bool c3 = graph->addConnection(
        {{feedbackReceiverNodeId, 1}, {nDelay->nodeID, 1}}, updateKind);

    feedbackBridgeReady = c0 && c1 && c2 && c3;
    if (!feedbackBridgeReady) {
      graph->removeNode(feedbackSenderNodeId, updateKind);
      graph->removeNode(feedbackReceiverNodeId, updateKind);
      feedbackSharedBuffer.reset();
    }
  } else {
    if (nFeedbackSender) {
      graph->removeNode(nFeedbackSender->nodeID, updateKind);
    }
    if (nFeedbackReceiver) {
      graph->removeNode(nFeedbackReceiver->nodeID, updateKind);
    }
    feedbackSharedBuffer.reset();
  }

  // Store IDs in Registry and Map to Graph IDs
  // We cannot use addToGraph() because we already hold the lock.

  // Osc
  resultIds[0] = registry.add(NodeType::Oscillator, nOsc->getProcessor());
  idToGraphNode[resultIds[0]] = nOsc->nodeID;

  // Filter
  resultIds[1] = registry.add(NodeType::BiquadFilter, nFilter->getProcessor());
  idToGraphNode[resultIds[1]] = nFilter->nodeID;

  // Gain
  resultIds[2] = registry.add(NodeType::Gain, nGain->getProcessor());
  idToGraphNode[resultIds[2]] = nGain->nodeID;

  // Panner
  resultIds[3] = registry.add(NodeType::StereoPanner, nPanner->getProcessor());
  idToGraphNode[resultIds[3]] = nPanner->nodeID;

  // Delay
  resultIds[4] = registry.add(NodeType::Delay, nDelay->getProcessor());
  idToGraphNode[resultIds[4]] = nDelay->nodeID;

  // DelayFb
  resultIds[5] = registry.add(NodeType::Gain, nDelayFb->getProcessor());
  idToGraphNode[resultIds[5]] = nDelayFb->nodeID;

  // DelayWet
  resultIds[6] = registry.add(NodeType::Gain, nDelayWet->getProcessor());
  idToGraphNode[resultIds[6]] = nDelayWet->nodeID;

  if (feedbackBridgeReady && feedbackSharedBuffer) {
    FeedbackConnection conn;
    conn.srcId = resultIds[5]; // Delay feedback gain
    conn.dstId = resultIds[4]; // Delay node input
    conn.output = 0;
    conn.input = 0;
    conn.sender = feedbackSenderNodeId;
    conn.receiver = feedbackReceiverNodeId;
    conn.buffer = feedbackSharedBuffer;
    feedbackConnections.push_back(conn);
  }

  // Register machine-voice lifecycle group (root: oscillator).
  const int32_t rootId = resultIds[0];
  std::vector<int32_t> members;
  members.reserve(7);
  for (int i = 0; i < 7; ++i) {
    members.push_back(resultIds[i]);
  }
  machineVoiceGroups[rootId] = members;
  for (const auto memberId : members) {
    machineVoiceRootByNode[memberId] = rootId;
  }
}

void Engine::connect(int32_t srcId, int32_t dstId, int output, int input) {
  std::lock_guard<std::mutex> lock(graphMtx);
  constexpr auto updateKind = juce::AudioProcessorGraph::UpdateKind::async;
  juce::AudioProcessorGraph::NodeID srcNodeId, dstNodeId;
  if (srcId == 0)
    srcNodeId = inputNode->nodeID;
  else {
    auto it = idToGraphNode.find(srcId);
    if (it == idToGraphNode.end())
      return;
    srcNodeId = it->second;
  }
  if (dstId == 0)
    dstNodeId = outputNode->nodeID;
  else {
    auto it = idToGraphNode.find(dstId);
    if (it == idToGraphNode.end())
      return;
    dstNodeId = it->second;
  }

  auto attemptConnect = [&](int outPort, int inPort) -> bool {
    using Connection = juce::AudioProcessorGraph::Connection;
    using NodeAndChannel = juce::AudioProcessorGraph::NodeAndChannel;

    const Connection direct{
        NodeAndChannel{srcNodeId, outPort},
        NodeAndChannel{dstNodeId, inPort},
    };

    // Skip invalid/duplicate channels before cycle detection.
    if (!graph->canConnect(direct)) {
      return false;
    }

    // Pre-check for cycle using JUCE's isAnInputTo
    bool wouldCycle = graph->isAnInputTo(dstNodeId, srcNodeId);

    if (!wouldCycle) {
      bool ok = graph->addConnection(direct, updateKind);
      if (ok)
        return true;
    }

    // Cycle detected! Implement FeedbackBridge (1-block delay)
    WA_LOG("[wajuce] Cycle detected: %d:%d -> %d:%d. Creating bridge.", srcId,
           outPort, dstId, inPort);

    const double currentSampleRate = sampleRate.load(std::memory_order_relaxed);
    const int currentBufferSize = bufferSize.load(std::memory_order_relaxed);
    auto sharedBuf =
        std::make_shared<juce::AudioBuffer<float>>(1, currentBufferSize);
    sharedBuf->clear();

    auto senderProc = std::make_unique<FeedbackSenderProcessor>(sharedBuf);
    senderProc->setPlayConfigDetails(1, 1, currentSampleRate,
                                     currentBufferSize);
    senderProc->prepareToPlay(currentSampleRate, currentBufferSize);
    auto receiverProc = std::make_unique<FeedbackReceiverProcessor>(sharedBuf);
    receiverProc->setPlayConfigDetails(1, 1, currentSampleRate,
                                       currentBufferSize);
    receiverProc->prepareToPlay(currentSampleRate, currentBufferSize);

    auto senderNode =
        graph->addNode(std::move(senderProc), std::nullopt, updateKind);
    auto receiverNode =
        graph->addNode(std::move(receiverProc), std::nullopt, updateKind);
    if (!senderNode || !receiverNode) {
      WA_LOG("[wajuce] FeedbackBridge: addNode failed.");
      return false;
    }
    auto senderNID = senderNode->nodeID;
    auto receiverNID = receiverNode->nodeID;

    const Connection toSender{
        NodeAndChannel{srcNodeId, outPort},
        NodeAndChannel{senderNID, 0},
    };
    const Connection fromReceiver{
        NodeAndChannel{receiverNID, 0},
        NodeAndChannel{dstNodeId, inPort},
    };

    bool c1 = false;
    bool c2 = false;
    if (graph->canConnect(toSender) && graph->canConnect(fromReceiver)) {
      c1 = graph->addConnection(toSender, updateKind);
      c2 = graph->addConnection(fromReceiver, updateKind);
    }

    if (c1 && c2) {
      WA_LOG("[wajuce] FeedbackBridge OK for %d -> %d", srcId, dstId);
      FeedbackConnection conn;
      conn.srcId = srcId;
      conn.dstId = dstId;
      conn.output = outPort;
      conn.input = inPort;
      conn.sender = senderNID;
      conn.receiver = receiverNID;
      conn.buffer = sharedBuf;
      feedbackConnections.push_back(conn);
      return true;
    } else {
      WA_LOG("[wajuce] FeedbackBridge failed.");
      graph->removeNode(senderNID, updateKind);
      graph->removeNode(receiverNID, updateKind);
      return false;
    }
  };

  bool isSplitter = false;
  bool isMerger = false;
  {
    std::lock_guard<std::recursive_mutex> registryLock(registry.getMutex());
    auto *srcEntry = registry.get(srcId);
    auto *dstEntry = registry.get(dstId);
    isSplitter = srcEntry && srcEntry->type == NodeType::ChannelSplitter;
    isMerger = dstEntry && dstEntry->type == NodeType::ChannelMerger;
  }

  if (isSplitter || isMerger) {
    attemptConnect(output, input);
  } else {
    // Connect only channels that are valid for both endpoints.
    auto *srcNode = graph->getNodeForId(srcNodeId);
    auto *dstNode = graph->getNodeForId(dstNodeId);
    if (!srcNode || !dstNode) {
      return;
    }

    const int srcTotalOut =
        srcNode->getProcessor()->getMainBusNumOutputChannels();
    const int dstTotalIn =
        dstNode->getProcessor()->getMainBusNumInputChannels();
    const int availableOut = juce::jmax(0, srcTotalOut - output);
    const int availableIn = juce::jmax(0, dstTotalIn - input);
    const int channelsToConnect = juce::jmin(availableOut, availableIn);

    for (int i = 0; i < channelsToConnect; ++i) {
      attemptConnect(output + i, input + i);
    }
  }
}

void Engine::disconnect(int32_t srcId, int32_t dstId) {
  std::lock_guard<std::mutex> lock(graphMtx);
  constexpr auto updateKind = juce::AudioProcessorGraph::UpdateKind::async;
  auto srcIt = idToGraphNode.find(srcId);
  auto dstIt = idToGraphNode.find(dstId);
  juce::AudioProcessorGraph::NodeID src =
      (srcId == 0) ? inputNode->nodeID
                   : (srcIt != idToGraphNode.end()
                          ? srcIt->second
                          : juce::AudioProcessorGraph::NodeID{});
  juce::AudioProcessorGraph::NodeID dst =
      (dstId == 0) ? outputNode->nodeID
                   : (dstIt != idToGraphNode.end()
                          ? dstIt->second
                          : juce::AudioProcessorGraph::NodeID{});

  auto connections = graph->getConnections();
  for (const auto &conn : connections) {
    if (conn.source.nodeID == src && conn.destination.nodeID == dst) {
      graph->removeConnection(conn, updateKind);
    }
  }

  // Cleanup feedback bridges between these specific nodes
  for (auto fit = feedbackConnections.begin();
       fit != feedbackConnections.end();) {
    if (fit->srcId == srcId && fit->dstId == dstId) {
      graph->removeNode(fit->sender, updateKind);
      graph->removeNode(fit->receiver, updateKind);
      fit = feedbackConnections.erase(fit);
    } else {
      ++fit;
    }
  }
}

void Engine::disconnectAll(int32_t srcId) {
  std::lock_guard<std::mutex> lock(graphMtx);
  constexpr auto updateKind = juce::AudioProcessorGraph::UpdateKind::async;
  auto it = idToGraphNode.find(srcId);
  if (it == idToGraphNode.end())
    return;
  juce::AudioProcessorGraph::NodeID src = it->second;
  auto connections = graph->getConnections();
  for (auto &conn : connections) {
    if (conn.source.nodeID == src)
      graph->removeConnection(conn, updateKind);
  }

  // Cleanup all feedback bridges originating from this node
  for (auto fit = feedbackConnections.begin();
       fit != feedbackConnections.end();) {
    if (fit->srcId == srcId) {
      graph->removeNode(fit->sender, updateKind);
      graph->removeNode(fit->receiver, updateKind);
      fit = feedbackConnections.erase(fit);
    } else {
      ++fit;
    }
  }
}

void Engine::processAutomation(double startTime, double sr, int numSamples) {
  // Never block the audio thread on UI-side parameter writes.
  std::unique_lock<std::recursive_mutex> lock(registry.getMutex(),
                                              std::try_to_lock);
  if (!lock.owns_lock()) {
    return;
  }

  for (auto &nodePair : registry.getNodes()) {
    auto &entry = nodePair.second;

    // Reset automation flags for this block
    if (entry.type == NodeType::Gain)
      entry.asGain()->isAutomated = false;
    else if (entry.type == NodeType::Delay)
      entry.asDelay()->isAutomated = false;

    for (auto &tl_pair : entry.timelines) {
      const std::string &param = tl_pair.first;

      switch (entry.type) {
      case NodeType::Gain: {
        auto *g = entry.asGain();
        if (param == "gain" && g) {
          if (g->sampleAccurateGains.size() >= (size_t)numSamples) {
            const float currentGain = g->gain.load(std::memory_order_relaxed);
            std::fill_n(g->sampleAccurateGains.begin(), numSamples,
                        currentGain);
            g->gain = tl_pair.second->processBlock(startTime, sr, numSamples,
                                                   g->sampleAccurateGains.data());
            g->isAutomated = true;
          } else {
            g->gain = tl_pair.second->processBlock(startTime, sr, numSamples);
          }
        }
        break;
      }
      case NodeType::Oscillator: {
        float val = tl_pair.second->processBlock(startTime, sr, numSamples);
        if (param == "frequency")
          entry.asOsc()->frequency = val;
        else if (param == "detune")
          entry.asOsc()->detune = val;
        break;
      }
      case NodeType::BiquadFilter: {
        float val = tl_pair.second->processBlock(startTime, sr, numSamples);
        if (param == "frequency")
          entry.asFilter()->frequency = val;
        else if (param == "Q")
          entry.asFilter()->Q = val;
        else if (param == "gain")
          entry.asFilter()->gain = val;
        break;
      }
      case NodeType::Delay: {
        auto *d = entry.asDelay();
        if (param == "delayTime" && d) {
          if (d->sampleAccurateDelayTimes.size() >= (size_t)numSamples) {
            const float currentDelay =
                d->delayTime.load(std::memory_order_relaxed);
            std::fill_n(d->sampleAccurateDelayTimes.begin(), numSamples,
                        currentDelay);
            d->delayTime = tl_pair.second->processBlock(
                startTime, sr, numSamples, d->sampleAccurateDelayTimes.data());
            d->isAutomated = true;
          } else {
            d->delayTime = tl_pair.second->processBlock(startTime, sr, numSamples);
          }
        } else if (param == "feedback") {
          d->feedback = tl_pair.second->processBlock(startTime, sr, numSamples);
        }
        break;
      }
      case NodeType::StereoPanner:
        if (param == "pan")
          entry.asPanner()->pan =
              tl_pair.second->processBlock(startTime, sr, numSamples);
        break;
      case NodeType::BufferSource: {
        float val = tl_pair.second->processBlock(startTime, sr, numSamples);
        if (param == "playbackRate")
          entry.asBufferSource()->playbackRate = val;
        else if (param == "detune")
          entry.asBufferSource()->detune = val;
        else if (param == "decay")
          entry.asBufferSource()->decay = val;
        break;
      }
      default:
        tl_pair.second->processBlock(startTime, sr, numSamples);
        break;
      }
    }
  }
}

void Engine::paramSet(int32_t nodeId, const char *param, float value) {
  std::lock_guard<std::recursive_mutex> lock(registry.getMutex());
  auto *entry = registry.get(nodeId);
  if (!entry)
    return;

  std::string p(param);
  auto *tl = entry->getOrCreateTimeline(param);
  if (tl)
    tl->setLastValue(value);

  // Immediate update if not automated or to set base value
  switch (entry->type) {
  case NodeType::Gain:
    if (p == "gain")
      entry->asGain()->gain = value;
    break;
  case NodeType::Oscillator:
    if (p == "frequency")
      entry->asOsc()->frequency = value;
    else if (p == "detune")
      entry->asOsc()->detune = value;
    break;
  case NodeType::BiquadFilter:
    if (p == "frequency")
      entry->asFilter()->frequency = value;
    else if (p == "Q")
      entry->asFilter()->Q = value;
    else if (p == "gain")
      entry->asFilter()->gain = value;
    break;
  case NodeType::Delay:
    if (p == "delayTime")
      entry->asDelay()->delayTime = value;
    else if (p == "feedback")
      entry->asDelay()->feedback = value;
    break;
  case NodeType::StereoPanner:
    if (p == "pan")
      entry->asPanner()->pan = value;
    break;
  case NodeType::BufferSource:
    if (p == "playbackRate")
      entry->asBufferSource()->playbackRate = value;
    else if (p == "detune")
      entry->asBufferSource()->detune = value;
    else if (p == "decay")
      entry->asBufferSource()->decay = value;
    break;
  default:
    break;
  }
}

void Engine::paramSetAtTime(int32_t nodeId, const char *param, float v,
                            double t) {
  std::lock_guard<std::recursive_mutex> lock(registry.getMutex());
  auto *entry = registry.get(nodeId);
  if (!entry)
    return;
  auto *tl = entry->getOrCreateTimeline(param);
  if (tl)
    tl->setValueAtTime(v, t);
}
void Engine::paramLinearRamp(int32_t nid, const char *p, float v, double te) {
  std::lock_guard<std::recursive_mutex> lock(registry.getMutex());
  auto *entry = registry.get(nid);
  if (!entry)
    return;
  auto *tl = entry->getOrCreateTimeline(p);
  if (tl)
    tl->linearRampToValueAtTime(v, te);
}
void Engine::paramExpRamp(int nid, const char *p, float v, double te) {
  std::lock_guard<std::recursive_mutex> lock(registry.getMutex());
  auto *entry = registry.get(nid);
  if (!entry)
    return;
  auto *tl = entry->getOrCreateTimeline(p);
  if (tl)
    tl->exponentialRampToValueAtTime(v, te);
}
void Engine::paramSetTarget(int nid, const char *p, float tgt, double ts,
                            float tc) {
  std::lock_guard<std::recursive_mutex> lock(registry.getMutex());
  auto *entry = registry.get(nid);
  if (!entry)
    return;
  auto *tl = entry->getOrCreateTimeline(p);
  if (tl)
    tl->setTargetAtTime(tgt, ts, tc);
}
void Engine::paramCancel(int nid, const char *p, double tc) {
  std::lock_guard<std::recursive_mutex> lock(registry.getMutex());
  auto *entry = registry.get(nid);
  if (!entry)
    return;
  auto *tl = entry->getOrCreateTimeline(p);
  if (tl)
    tl->cancelScheduledValues(tc);
}

void Engine::paramCancelAndHold(int nid, const char *p, double t) {
  std::lock_guard<std::recursive_mutex> lock(registry.getMutex());
  auto *entry = registry.get(nid);
  if (!entry)
    return;
  auto *tl = entry->getOrCreateTimeline(p);
  if (!tl)
    return;
  tl->setLastValue(entry->getParam(p));
  tl->cancelAndHoldAtTime(t);
}

void Engine::oscSetType(int32_t nodeId, int type) {
  std::lock_guard<std::recursive_mutex> lock(registry.getMutex());
  auto *entry = registry.get(nodeId);
  if (entry && entry->type == NodeType::Oscillator)
    entry->asOsc()->type = type;
}
void Engine::oscStart(int32_t nodeId, double when) {
  std::lock_guard<std::recursive_mutex> lock(registry.getMutex());
  auto *entry = registry.get(nodeId);
  if (entry && entry->type == NodeType::Oscillator)
    entry->asOsc()->start(when);
}
void Engine::oscStop(int32_t nid, double w) {
  std::lock_guard<std::recursive_mutex> lock(registry.getMutex());
  auto *entry = registry.get(nid);
  if (entry && entry->type == NodeType::Oscillator)
    entry->asOsc()->stop(w);
}

void Engine::oscSetPeriodicWave(int32_t nid, const float *real,
                                const float *imag, int32_t len) {
  std::lock_guard<std::recursive_mutex> lock(registry.getMutex());
  auto *entry = registry.get(nid);
  if (entry && entry->type == NodeType::Oscillator) {
    // Generate wavetable via additive synthesis (Inverse Fourier Approximation)
    // Standard table size for good quality
    const int tableSize = 4096;
    std::vector<float> table(tableSize, 0.0f);

    // x(t) = sum(real[k] * cos(2pi*k*t) + imag[k] * sin(2pi*k*t))
    // We start from k=1 usually as k=0 is DC offset.
    // If len <= 0, we do nothing or clear.

    if (len > 0) {
      // Handle DC offset if present (real[0])
      float dc = real[0];

      for (int i = 0; i < tableSize; ++i) {
        double t = (double)i / tableSize;
        double val = dc;

        for (int k = 1; k < len; ++k) {
          // Optimization: Precompute 2PI * k
          double phase = 2.0 * juce::MathConstants<double>::pi * k * t;
          val += real[k] * std::cos(phase) + imag[k] * std::sin(phase);
        }
        table[i] = (float)val;
      }

      // Normalize to [-1, 1] to prevent clipping
      float maxVal = 0.0f;
      for (float v : table)
        maxVal = std::max(maxVal, std::abs(v));
      if (maxVal > 1e-6f) {
        float scale = 1.0f / maxVal;
        for (float &v : table)
          v *= scale;
      }
    }

    entry->asOsc()->setPeriodicWave(table.data(), tableSize);
  }
}

void Engine::filterSetType(int32_t nid, int type) {
  std::lock_guard<std::recursive_mutex> lock(registry.getMutex());
  auto *entry = registry.get(nid);
  if (entry && entry->type == NodeType::BiquadFilter)
    entry->asFilter()->filterType = type;
}

void Engine::bufferSourceSetBuffer(int32_t nid, const float *d, int f, int c,
                                   int s) {
  std::lock_guard<std::recursive_mutex> lock(registry.getMutex());
  auto *entry = registry.get(nid);
  if (entry && entry->type == NodeType::BufferSource)
    entry->asBufferSource()->setBuffer(d, f, c, s);
}
void Engine::bufferSourceStart(int32_t nid, double w) {
  std::lock_guard<std::recursive_mutex> lock(registry.getMutex());
  auto *entry = registry.get(nid);
  if (entry && entry->type == NodeType::BufferSource)
    entry->asBufferSource()->start(w);
}
void Engine::bufferSourceStop(int32_t nid, double w) {
  std::lock_guard<std::recursive_mutex> lock(registry.getMutex());
  auto *entry = registry.get(nid);
  if (entry && entry->type == NodeType::BufferSource)
    entry->asBufferSource()->stop(w);
}
void Engine::bufferSourceSetLoop(int32_t nid, bool l) {
  std::lock_guard<std::recursive_mutex> lock(registry.getMutex());
  auto *entry = registry.get(nid);
  if (entry && entry->type == NodeType::BufferSource)
    entry->asBufferSource()->setLoop(l);
}

void Engine::analyserSetFftSize(int32_t nid, int32_t s) {
  std::lock_guard<std::recursive_mutex> lock(registry.getMutex());
  auto *entry = registry.get(nid);
  if (entry && entry->type == NodeType::Analyser)
    entry->asAnalyser()->setFftSize(s);
}
void Engine::analyserGetByteFreqData(int32_t nid, uint8_t *d, int l) {
  std::lock_guard<std::recursive_mutex> lock(registry.getMutex());
  auto *entry = registry.get(nid);
  if (entry && entry->type == NodeType::Analyser)
    entry->asAnalyser()->getByteFrequencyData(d, l);
}
void Engine::analyserGetByteTimeData(int32_t nid, uint8_t *d, int l) {
  std::lock_guard<std::recursive_mutex> lock(registry.getMutex());
  auto *entry = registry.get(nid);
  if (entry && entry->type == NodeType::Analyser)
    entry->asAnalyser()->getByteTimeDomainData(d, l);
}
void Engine::analyserGetFloatFreqData(int32_t nid, float *d, int l) {
  std::lock_guard<std::recursive_mutex> lock(registry.getMutex());
  auto *entry = registry.get(nid);
  if (entry && entry->type == NodeType::Analyser)
    entry->asAnalyser()->getFloatFrequencyData(d, l);
}
void Engine::analyserGetFloatTimeData(int32_t nid, float *d, int l) {
  std::lock_guard<std::recursive_mutex> lock(registry.getMutex());
  auto *entry = registry.get(nid);
  if (entry && entry->type == NodeType::Analyser)
    entry->asAnalyser()->getFloatTimeDomainData(d, l);
}

void Engine::waveShaperSetCurve(int32_t nid, const float *d, int l) {
  std::lock_guard<std::recursive_mutex> lock(registry.getMutex());
  auto *entry = registry.get(nid);
  if (entry && entry->type == NodeType::WaveShaper)
    entry->asWaveShaper()->setCurve(d, l);
}
void Engine::waveShaperSetOversample(int32_t nid, int t) {
  std::lock_guard<std::recursive_mutex> lock(registry.getMutex());
  auto *entry = registry.get(nid);
  if (entry && entry->type == NodeType::WaveShaper)
    entry->asWaveShaper()->setOversample(t);
}

} // namespace wajuce

extern "C" {
using namespace wajuce;
FFI_PLUGIN_EXPORT int32_t wajuce_context_create(int32_t sr, int32_t bs,
                                                int32_t inCh, int32_t outCh) {
  auto engine = wajuce::runOnJuceMessageThreadSync([&]() {
    return std::make_shared<wajuce::Engine>((double)sr, bs, inCh, outCh);
  });
  std::lock_guard<std::mutex> lock(wajuce::g_engineMtx);
  int32_t id = wajuce::g_nextCtxId++;
  wajuce::g_engines[id] = std::move(engine);
  return id;
}
FFI_PLUGIN_EXPORT void wajuce_context_destroy(int32_t id) {
  wajuce::runOnJuceMessageThreadSync([&]() {
    std::lock_guard<std::mutex> lock(wajuce::g_engineMtx);
    wajuce::g_engines.erase(id);
  });
}
FFI_PLUGIN_EXPORT double wajuce_context_get_time(int32_t id) {
  auto e = getEngine(id);
  return e ? e->getCurrentTime() : 0.0;
}
FFI_PLUGIN_EXPORT int32_t wajuce_context_get_live_node_count(int32_t id) {
  auto e = getEngine(id);
  return e ? e->getLiveNodeCount() : 0;
}
FFI_PLUGIN_EXPORT int32_t wajuce_context_get_feedback_bridge_count(int32_t id) {
  auto e = getEngine(id);
  return e ? e->getFeedbackBridgeCount() : 0;
}
FFI_PLUGIN_EXPORT int32_t
wajuce_context_get_machine_voice_group_count(int32_t id) {
  auto e = getEngine(id);
  return e ? e->getMachineVoiceGroupCount() : 0;
}
FFI_PLUGIN_EXPORT double wajuce_context_get_sample_rate(int32_t id) {
  auto e = getEngine(id);
  return e ? e->getSampleRate() : 44100.0;
}
FFI_PLUGIN_EXPORT int32_t wajuce_context_get_bit_depth(int32_t id) {
  auto e = getEngine(id);
  return e ? e->getCurrentBitDepth() : 32;
}
FFI_PLUGIN_EXPORT int32_t
wajuce_context_set_preferred_sample_rate(int32_t id, double preferred_sr) {
  auto e = getEngine(id);
  return (e && e->setPreferredSampleRate(preferred_sr)) ? 1 : 0;
}
FFI_PLUGIN_EXPORT int32_t
wajuce_context_set_preferred_bit_depth(int32_t id, int32_t preferred_bit_depth) {
  auto e = getEngine(id);
  return (e && e->setPreferredBitDepth(preferred_bit_depth)) ? 1 : 0;
}
FFI_PLUGIN_EXPORT int32_t wajuce_context_get_state(int32_t id) {
  auto e = getEngine(id);
  return e ? e->getState() : 2;
}
FFI_PLUGIN_EXPORT void wajuce_context_resume(int32_t id) {
  auto e = getEngine(id);
  if (e)
    e->resume();
}
FFI_PLUGIN_EXPORT void wajuce_context_suspend(int32_t id) {
  auto e = getEngine(id);
  if (e)
    e->suspend();
}
FFI_PLUGIN_EXPORT void wajuce_context_close(int32_t id) {
  auto e = getEngine(id);
  if (e)
    e->close();
}
FFI_PLUGIN_EXPORT int32_t wajuce_context_get_destination_id(int32_t id) {
  auto e = getEngine(id);
  return e ? e->getDestinationId() : 0;
}
FFI_PLUGIN_EXPORT void wajuce_create_machine_voice(int32_t ctx_id,
                                                   int32_t *result_ids) {
  auto engine = wajuce::getEngine(ctx_id);
  if (engine)
    engine->createMachineVoice(result_ids);
}

FFI_PLUGIN_EXPORT void wajuce_context_remove_node(int32_t cid, int32_t nid) {
  auto e = getEngine(cid);
  if (e)
    e->removeNode(nid);
}
FFI_PLUGIN_EXPORT int32_t wajuce_create_gain(int32_t id) {
  auto e = getEngine(id);
  return e ? e->createGain() : -1;
}
FFI_PLUGIN_EXPORT int32_t wajuce_create_oscillator(int32_t id) {
  auto e = getEngine(id);
  return e ? e->createOscillator() : -1;
}
FFI_PLUGIN_EXPORT int32_t wajuce_create_biquad_filter(int32_t id) {
  auto e = getEngine(id);
  return e ? e->createBiquadFilter() : -1;
}
FFI_PLUGIN_EXPORT int32_t wajuce_create_compressor(int32_t id) {
  auto e = getEngine(id);
  return e ? e->createCompressor() : -1;
}
FFI_PLUGIN_EXPORT int32_t wajuce_create_delay(int32_t id, float d) {
  auto e = getEngine(id);
  return e ? e->createDelay(d) : -1;
}
FFI_PLUGIN_EXPORT int32_t wajuce_create_buffer_source(int32_t id) {
  auto e = getEngine(id);
  return e ? e->createBufferSource() : -1;
}
FFI_PLUGIN_EXPORT int32_t wajuce_create_analyser(int32_t id) {
  auto e = getEngine(id);
  return e ? e->createAnalyser() : -1;
}
FFI_PLUGIN_EXPORT int32_t wajuce_create_stereo_panner(int32_t id) {
  auto e = getEngine(id);
  return e ? e->createStereoPanner() : -1;
}
FFI_PLUGIN_EXPORT int32_t wajuce_create_wave_shaper(int32_t id) {
  auto e = getEngine(id);
  return e ? e->createWaveShaper() : -1;
}
FFI_PLUGIN_EXPORT int32_t wajuce_create_media_stream_source(int32_t id) {
  auto e = getEngine(id);
  return e ? e->createMediaStreamSource() : -1;
}
FFI_PLUGIN_EXPORT int32_t wajuce_create_media_stream_destination(int32_t id) {
  auto e = getEngine(id);
  return e ? e->createMediaStreamDestination() : -1;
}
FFI_PLUGIN_EXPORT int32_t wajuce_create_worklet_bridge(int32_t id,
                                                       int32_t inputs,
                                                       int32_t outputs) {
  auto e = getEngine(id);
  return e ? e->createWorkletBridge(inputs, outputs) : -1;
}

FFI_PLUGIN_EXPORT float *wajuce_worklet_get_buffer_ptr(int32_t ctx_id,
                                                       int32_t bridge_id,
                                                       int32_t direction,
                                                       int32_t channel) {
  auto *rb = getWorkletRingBuffer(ctx_id, bridge_id, direction, channel);
  return rb ? rb->getBufferRawPtr() : nullptr;
}

FFI_PLUGIN_EXPORT int32_t wajuce_worklet_get_input_channel_count(
    int32_t ctx_id, int32_t bridge_id) {
  auto e = getEngine(ctx_id);
  return e ? e->getWorkletBridgeInputChannelCount(bridge_id) : 0;
}

FFI_PLUGIN_EXPORT int32_t wajuce_worklet_get_output_channel_count(
    int32_t ctx_id, int32_t bridge_id) {
  auto e = getEngine(ctx_id);
  return e ? e->getWorkletBridgeOutputChannelCount(bridge_id) : 0;
}

FFI_PLUGIN_EXPORT int32_t wajuce_worklet_get_read_pos(int32_t ctx_id,
                                                      int32_t bridge_id,
                                                      int32_t direction,
                                                      int32_t channel) {
  auto *rb = getWorkletRingBuffer(ctx_id, bridge_id, direction, channel);
  return rb ? rb->getReadPos() : 0;
}

FFI_PLUGIN_EXPORT int32_t wajuce_worklet_get_write_pos(int32_t ctx_id,
                                                       int32_t bridge_id,
                                                       int32_t direction,
                                                       int32_t channel) {
  auto *rb = getWorkletRingBuffer(ctx_id, bridge_id, direction, channel);
  return rb ? rb->getWritePos() : 0;
}

FFI_PLUGIN_EXPORT void wajuce_worklet_set_read_pos(int32_t ctx_id,
                                                   int32_t bridge_id,
                                                   int32_t direction,
                                                   int32_t channel,
                                                   int32_t value) {
  auto *rb = getWorkletRingBuffer(ctx_id, bridge_id, direction, channel);
  if (rb)
    rb->setReadPos(value);
}

FFI_PLUGIN_EXPORT void wajuce_worklet_set_write_pos(int32_t ctx_id,
                                                    int32_t bridge_id,
                                                    int32_t direction,
                                                    int32_t channel,
                                                    int32_t value) {
  auto *rb = getWorkletRingBuffer(ctx_id, bridge_id, direction, channel);
  if (rb)
    rb->setWritePos(value);
}

FFI_PLUGIN_EXPORT int32_t wajuce_worklet_get_capacity(int32_t ctx_id,
                                                      int32_t bridge_id) {
  auto e = getEngine(ctx_id);
  return e ? e->getWorkletBridgeCapacity(bridge_id) : 0;
}

FFI_PLUGIN_EXPORT void wajuce_worklet_release_bridge(int32_t ctx_id,
                                                     int32_t bridge_id) {
  auto e = getEngine(ctx_id);
  if (e)
    e->releaseWorkletBridge(bridge_id);
}
FFI_PLUGIN_EXPORT int32_t wajuce_create_channel_splitter(int32_t id,
                                                         int32_t outputs) {
  auto e = getEngine(id);
  return e ? e->createChannelSplitter(outputs) : -1;
}
FFI_PLUGIN_EXPORT int32_t wajuce_create_channel_merger(int32_t id,
                                                       int32_t inputs) {
  auto e = getEngine(id);
  return e ? e->createChannelMerger(inputs) : -1;
}

FFI_PLUGIN_EXPORT void wajuce_connect(int32_t cid, int32_t sid, int32_t did,
                                      int32_t o, int32_t i) {
  auto e = getEngine(cid);
  if (e)
    e->connect(sid, did, o, i);
}
FFI_PLUGIN_EXPORT void wajuce_disconnect(int32_t cid, int32_t sid,
                                         int32_t did) {
  auto e = getEngine(cid);
  if (e)
    e->disconnect(sid, did);
}
FFI_PLUGIN_EXPORT void wajuce_disconnect_all(int32_t cid, int32_t sid) {
  auto e = getEngine(cid);
  if (e)
    e->disconnectAll(sid);
}

FFI_PLUGIN_EXPORT void wajuce_param_set(int32_t nid, const char *p, float v) {
  auto e = wajuce::findEngineForNode(nid);
  if (e)
    e->paramSet(nid, p, v);
}
FFI_PLUGIN_EXPORT void wajuce_param_set_at_time(int32_t nid, const char *p,
                                                float v, double t) {
  auto e = wajuce::findEngineForNode(nid);
  if (e)
    e->paramSetAtTime(nid, p, v, t);
}
FFI_PLUGIN_EXPORT void wajuce_param_linear_ramp(int32_t nid, const char *p,
                                                float v, double te) {
  auto e = wajuce::findEngineForNode(nid);
  if (e)
    e->paramLinearRamp(nid, p, v, te);
}
FFI_PLUGIN_EXPORT void wajuce_param_exp_ramp(int32_t nid, const char *p,
                                             float v, double te) {
  auto e = wajuce::findEngineForNode(nid);
  if (e)
    e->paramExpRamp(nid, p, v, te);
}
FFI_PLUGIN_EXPORT void wajuce_param_set_target(int32_t nid, const char *p,
                                               float tgt, double ts, float tc) {
  auto e = wajuce::findEngineForNode(nid);
  if (e)
    e->paramSetTarget(nid, p, tgt, ts, tc);
}
FFI_PLUGIN_EXPORT void wajuce_param_cancel(int32_t nid, const char *p,
                                           double tc) {
  auto e = wajuce::findEngineForNode(nid);
  if (e)
    e->paramCancel(nid, p, tc);
}
FFI_PLUGIN_EXPORT void wajuce_param_cancel_and_hold(int32_t nid, const char *p,
                                                    double t) {
  auto e = wajuce::findEngineForNode(nid);
  if (e)
    e->paramCancelAndHold(nid, p, t);
}

FFI_PLUGIN_EXPORT void wajuce_osc_set_type(int32_t nid, int32_t t) {
  auto e = wajuce::findEngineForNode(nid);
  if (e)
    e->oscSetType(nid, t);
}
FFI_PLUGIN_EXPORT void wajuce_osc_start(int32_t nid, double w) {
  auto e = wajuce::findEngineForNode(nid);
  if (e)
    e->oscStart(nid, w);
}
FFI_PLUGIN_EXPORT void wajuce_osc_stop(int32_t nid, double w) {
  auto e = wajuce::findEngineForNode(nid);
  if (e)
    e->oscStop(nid, w);
}
FFI_PLUGIN_EXPORT void wajuce_osc_set_periodic_wave(int32_t nid,
                                                    const float *real,
                                                    const float *imag,
                                                    int32_t len) {
  auto e = wajuce::findEngineForNode(nid);
  if (e)
    e->oscSetPeriodicWave(nid, real, imag, len);
}

FFI_PLUGIN_EXPORT void wajuce_filter_set_type(int32_t nid, int32_t t) {
  auto e = wajuce::findEngineForNode(nid);
  if (e)
    e->filterSetType(nid, t);
}
FFI_PLUGIN_EXPORT void wajuce_buffer_source_set_buffer(int32_t nid,
                                                       const float *d,
                                                       int32_t f, int32_t c,
                                                       int32_t s) {
  auto e = wajuce::findEngineForNode(nid);
  if (e)
    e->bufferSourceSetBuffer(nid, d, f, c, s);
}
FFI_PLUGIN_EXPORT void wajuce_buffer_source_start(int32_t nid, double w) {
  auto e = wajuce::findEngineForNode(nid);
  if (e)
    e->bufferSourceStart(nid, w);
}
FFI_PLUGIN_EXPORT void wajuce_buffer_source_stop(int32_t nid, double w) {
  auto e = wajuce::findEngineForNode(nid);
  if (e)
    e->bufferSourceStop(nid, w);
}
FFI_PLUGIN_EXPORT void wajuce_buffer_source_set_loop(int32_t nid, int32_t l) {
  auto e = wajuce::findEngineForNode(nid);
  if (e)
    e->bufferSourceSetLoop(nid, l != 0);
}

FFI_PLUGIN_EXPORT void wajuce_analyser_set_fft_size(int32_t nid, int32_t s) {
  auto e = wajuce::findEngineForNode(nid);
  if (e)
    e->analyserSetFftSize(nid, s);
}
FFI_PLUGIN_EXPORT void wajuce_analyser_get_byte_freq(int32_t nid, uint8_t *d,
                                                     int32_t l) {
  auto e = wajuce::findEngineForNode(nid);
  if (e)
    e->analyserGetByteFreqData(nid, d, l);
}
FFI_PLUGIN_EXPORT void wajuce_analyser_get_byte_time(int32_t nid, uint8_t *d,
                                                     int32_t l) {
  auto e = wajuce::findEngineForNode(nid);
  if (e)
    e->analyserGetByteTimeData(nid, d, l);
}
FFI_PLUGIN_EXPORT void wajuce_analyser_get_float_freq(int32_t nid, float *d,
                                                      int32_t l) {
  auto e = wajuce::findEngineForNode(nid);
  if (e)
    e->analyserGetFloatFreqData(nid, d, l);
}
FFI_PLUGIN_EXPORT void wajuce_analyser_get_float_time(int32_t nid, float *d,
                                                      int32_t l) {
  auto e = wajuce::findEngineForNode(nid);
  if (e)
    e->analyserGetFloatTimeData(nid, d, l);
}

FFI_PLUGIN_EXPORT void wajuce_wave_shaper_set_curve(int32_t nid, const float *d,
                                                    int32_t l) {
  auto e = wajuce::findEngineForNode(nid);
  if (e)
    e->waveShaperSetCurve(nid, d, l);
}
FFI_PLUGIN_EXPORT void wajuce_wave_shaper_set_oversample(int32_t nid,
                                                         int32_t t) {
  auto e = wajuce::findEngineForNode(nid);
  if (e)
    e->waveShaperSetOversample(nid, t);
}

FFI_PLUGIN_EXPORT int32_t wajuce_decode_audio_data(const uint8_t *encoded_data,
                                                   int32_t len, float *out_data,
                                                   int32_t *out_frames,
                                                   int32_t *out_channels,
                                                   int32_t *out_sr) {
  juce::AudioFormatManager formatManager;
  formatManager.registerBasicFormats();

  auto stream = std::make_unique<juce::MemoryInputStream>(encoded_data,
                                                          (size_t)len, false);
  std::unique_ptr<juce::AudioFormatReader> reader(
      formatManager.createReaderFor(std::move(stream)));

  if (reader == nullptr)
    return -1;

  *out_frames = (int32_t)reader->lengthInSamples;
  *out_channels = (int32_t)reader->numChannels;
  *out_sr = (int32_t)reader->sampleRate;

  if (out_data != nullptr) {
    juce::AudioBuffer<float> buffer((int)reader->numChannels,
                                    (int)reader->lengthInSamples);
    reader->read(&buffer, 0, (int)reader->lengthInSamples, 0, true, true);

    // Pack data for Dart: [ch0_samp0..ch0_sampN, ch1_samp0..ch1_sampN, ...]
    for (int ch = 0; ch < (int)reader->numChannels; ++ch) {
      std::memcpy(out_data + ch * (size_t)reader->lengthInSamples,
                  buffer.getReadPointer(ch),
                  (size_t)reader->lengthInSamples * sizeof(float));
    }
  }

  return 0;
}

FFI_PLUGIN_EXPORT int32_t wajuce_midi_get_port_count(int32_t type) {
  return wajuce::runOnJuceMessageThreadSync([&]() -> int32_t {
    if (type == 0)
      return juce::MidiInput::getAvailableDevices().size();
    return juce::MidiOutput::getAvailableDevices().size();
  });
}

FFI_PLUGIN_EXPORT void wajuce_midi_get_port_name(int32_t type, int32_t index,
                                                 char *buffer,
                                                 int32_t max_len) {
  wajuce::runOnJuceMessageThreadSync([&]() {
    auto devices = (type == 0) ? juce::MidiInput::getAvailableDevices()
                               : juce::MidiOutput::getAvailableDevices();
    if (index >= 0 && index < devices.size()) {
      juce::String name = devices[index].name;
      name.copyToUTF8(buffer, (size_t)max_len);
    }
  });
}

FFI_PLUGIN_EXPORT void wajuce_midi_port_open(int32_t type, int32_t index) {
  wajuce::runOnJuceMessageThreadSync([&]() {
    std::lock_guard<std::mutex> lock(wajuce::g_midiMtx);
    auto devices = (type == 0) ? juce::MidiInput::getAvailableDevices()
                               : juce::MidiOutput::getAvailableDevices();
    if (index >= 0 && index < devices.size()) {
      if (type == 0) {
        if (wajuce::g_midiInputs.count(index))
          return;
        auto proxy = std::make_unique<wajuce::MidiInputProxy>(index, nullptr);
        auto input =
            juce::MidiInput::openDevice(devices[index].identifier, proxy.get());
        if (input) {
          proxy->input = std::move(input);
          proxy->input->start();
          wajuce::g_midiInputs[index] = std::move(proxy);
        }
      } else {
        if (wajuce::g_midiOutputs.count(index))
          return;
        auto output = juce::MidiOutput::openDevice(devices[index].identifier);
        if (output) {
          wajuce::g_midiOutputs[index] = std::move(output);
        }
      }
    }
  });
}

FFI_PLUGIN_EXPORT void wajuce_midi_port_close(int32_t type, int32_t index) {
  std::lock_guard<std::mutex> lock(wajuce::g_midiMtx);
  if (type == 0) {
    wajuce::g_midiInputs.erase(index);
  } else {
    wajuce::g_midiOutputs.erase(index);
  }
}

FFI_PLUGIN_EXPORT void wajuce_midi_output_send(int32_t index,
                                               const uint8_t *data, int32_t len,
                                               double timestamp) {
  std::lock_guard<std::mutex> lock(wajuce::g_midiMtx);
  auto it = wajuce::g_midiOutputs.find(index);
  if (it != wajuce::g_midiOutputs.end()) {
    it->second->sendMessageNow(juce::MidiMessage(data, len));
  }
}

FFI_PLUGIN_EXPORT void wajuce_midi_set_callback(wajuce_midi_callback_t cb) {
  wajuce::g_midiGlobalCallback = cb;
}

FFI_PLUGIN_EXPORT void wajuce_midi_dispose() {
  std::lock_guard<std::mutex> lock(wajuce::g_midiMtx);
  wajuce::g_midiInputs.clear();
  wajuce::g_midiOutputs.clear();
}

} // extern "C"
