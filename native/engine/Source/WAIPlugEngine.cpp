#include "WAIPlugEngine.h"

#include "../../../src/wajuce.h"

#if __has_include("IPlugConstants.h")
#include "IPlugConstants.h"
#endif

#if defined(WAJUCE_USE_RTMIDI) && WAJUCE_USE_RTMIDI
#include "RtMidi.h"
#endif

#if defined(__APPLE__)
#include <AudioToolbox/AudioToolbox.h>
#include <CoreFoundation/CoreFoundation.h>
#endif

#if defined(WAJUCE_USE_APPLE_AUDIOUNIT) && WAJUCE_USE_APPLE_AUDIOUNIT &&        \
    defined(__OBJC__)
#import <AVFoundation/AVFoundation.h>
#endif

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdio>
#include <cstring>
#include <exception>
#include <limits>
#include <numeric>
#include <queue>
#include <unordered_set>

#if defined(WAJUCE_USE_APPLE_AUDIOUNIT) && WAJUCE_USE_APPLE_AUDIOUNIT &&        \
    defined(__OBJC__)
#include <dispatch/dispatch.h>
#endif

namespace {

constexpr double kPi = 3.14159265358979323846264338327950288;
constexpr float kSilentFloor = 1.0e-12f;
constexpr float kNeutralDecaySeconds = 1.0e12f;

#define WA_LOG(fmt, ...) fprintf(stderr, "[wajuce] " fmt "\n", ##__VA_ARGS__)

float clampFloat(float v, float lo, float hi) {
  return std::max(lo, std::min(hi, v));
}

float decibelsToGain(float db) { return std::pow(10.0f, db / 20.0f); }

} // namespace

namespace wajuce {

std::unordered_map<int32_t, std::shared_ptr<Engine>> g_engines;
std::mutex g_engineMtx;
int32_t g_nextCtxId = 1;

std::shared_ptr<Engine> findEngineForNode(int32_t nodeId) {
  std::lock_guard<std::mutex> lock(g_engineMtx);
  for (auto &[_, engine] : g_engines) {
    if (engine && engine->containsNode(nodeId)) {
      return engine;
    }
  }
  return {};
}

static std::shared_ptr<Engine> getEngine(int32_t ctxId) {
  std::lock_guard<std::mutex> lock(g_engineMtx);
  auto it = g_engines.find(ctxId);
  return it == g_engines.end() ? nullptr : it->second;
}

void Engine::AudioBus::resize(int nextChannels, int nextFrames) {
  channels = std::max(1, nextChannels);
  frames = std::max(0, nextFrames);
  samples.assign(static_cast<size_t>(channels * frames), 0.0f);
}

void Engine::AudioBus::clear() {
  std::fill(samples.begin(), samples.end(), 0.0f);
}

float *Engine::AudioBus::channel(int ch) {
  if (ch < 0 || ch >= channels || frames <= 0) {
    return nullptr;
  }
  return samples.data() + static_cast<size_t>(ch * frames);
}

const float *Engine::AudioBus::channel(int ch) const {
  if (ch < 0 || ch >= channels || frames <= 0) {
    return nullptr;
  }
  return samples.data() + static_cast<size_t>(ch * frames);
}

static void setDefaultParam(Engine::Node &node, const char *name, float value) {
  node.paramValues[name] = value;
  auto timeline = std::make_unique<ParamTimeline>();
  timeline->setLastValue(value);
  node.timelines[name] = std::move(timeline);
}

Engine::Engine(double sr, int bs, int inCh, int outCh)
    : sampleRate(sr > 0.0 ? sr : 44100.0), bufferSize(std::max(32, bs)),
      inputChannels(std::max(0, inCh)), outputChannels(std::max(1, outCh)),
      renderChannels(std::max(1, outCh)) {
  Node destination;
  destination.id = 0;
  destination.kind = NodeKind::Destination;
  destination.inputCount = 1;
  destination.outputCount = 0;
  destination.current.resize(renderChannels, bufferSize.load());
  destination.previous.resize(renderChannels, bufferSize.load());
  nodes.emplace(0, std::move(destination));

  Node listener;
  listener.id = nextNodeId++;
  listener.kind = NodeKind::Listener;
  listener.inputCount = 0;
  listener.outputCount = 0;
  setDefaultParam(listener, "positionX", 0.0f);
  setDefaultParam(listener, "positionY", 0.0f);
  setDefaultParam(listener, "positionZ", 0.0f);
  setDefaultParam(listener, "forwardX", 0.0f);
  setDefaultParam(listener, "forwardY", 0.0f);
  setDefaultParam(listener, "forwardZ", -1.0f);
  setDefaultParam(listener, "upX", 0.0f);
  setDefaultParam(listener, "upY", 1.0f);
  setDefaultParam(listener, "upZ", 0.0f);
  listener.current.resize(renderChannels, bufferSize.load());
  listener.previous.resize(renderChannels, bufferSize.load());
  listenerNodeId = listener.id;
  nodes.emplace(listenerNodeId, std::move(listener));
}

Engine::~Engine() { close(); }

void Engine::resume() {
  if (state.load(std::memory_order_relaxed) == 2) {
    return;
  }
  state.store(1, std::memory_order_release);
#if defined(WAJUCE_USE_RTAUDIO) && WAJUCE_USE_RTAUDIO
  ensureRealtimeStream();
#endif
#if defined(WAJUCE_USE_APPLE_AUDIOUNIT) && WAJUCE_USE_APPLE_AUDIOUNIT
  ensureAppleAudioUnit();
#endif
}

void Engine::suspend() {
  if (state.load(std::memory_order_relaxed) != 2) {
    state.store(0, std::memory_order_release);
  }
#if defined(WAJUCE_USE_RTAUDIO) && WAJUCE_USE_RTAUDIO
  closeRealtimeStream();
#endif
#if defined(WAJUCE_USE_APPLE_AUDIOUNIT) && WAJUCE_USE_APPLE_AUDIOUNIT
  closeAppleAudioUnit();
#endif
}

void Engine::close() {
  state.store(2, std::memory_order_release);
#if defined(WAJUCE_USE_RTAUDIO) && WAJUCE_USE_RTAUDIO
  closeRealtimeStream();
#endif
#if defined(WAJUCE_USE_APPLE_AUDIOUNIT) && WAJUCE_USE_APPLE_AUDIOUNIT
  closeAppleAudioUnit();
#endif
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  connections.clear();
  nodes.clear();
}

int32_t Engine::getLiveNodeCount() {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  return static_cast<int32_t>(nodes.size());
}

int32_t Engine::getMachineVoiceGroupCount() {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  return static_cast<int32_t>(machineVoiceGroups.size());
}

bool Engine::setPreferredSampleRate(double preferredSampleRate) {
  if (preferredSampleRate <= 0.0) {
    return false;
  }
  sampleRate.store(preferredSampleRate, std::memory_order_release);
  return true;
}

bool Engine::setPreferredBitDepth(int bitDepth) {
  preferredBitDepth.store(std::max(2, std::min(32, bitDepth)),
                          std::memory_order_release);
  return true;
}

int32_t Engine::addNode(Node node) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  const int32_t id = nextNodeId++;
  node.id = id;
  node.current.resize(renderChannels, bufferSize.load());
  node.previous.resize(renderChannels, bufferSize.load());
  nodes.emplace(id, std::move(node));
  return id;
}

Engine::Node *Engine::findNodeUnlocked(int32_t nodeId) {
  auto it = nodes.find(nodeId);
  return it == nodes.end() ? nullptr : &it->second;
}

const Engine::Node *Engine::findNodeUnlocked(int32_t nodeId) const {
  auto it = nodes.find(nodeId);
  return it == nodes.end() ? nullptr : &it->second;
}

bool Engine::containsNode(int32_t nodeId) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  return nodes.find(nodeId) != nodes.end();
}

ParamTimeline &Engine::timelineFor(Node &node, const std::string &param) {
  auto it = node.timelines.find(param);
  if (it == node.timelines.end()) {
    auto timeline = std::make_unique<ParamTimeline>();
    timeline->setLastValue(currentParam(node, param.c_str(), 0.0f));
    it = node.timelines.emplace(param, std::move(timeline)).first;
  }
  return *it->second;
}

float Engine::currentParam(Node &node, const char *param, float fallback) {
  auto it = node.paramValues.find(param);
  return it == node.paramValues.end() ? fallback : it->second;
}

void Engine::paramBlock(Node &node, const char *param, float fallback,
                        double blockStart, int frames,
                        std::vector<int32_t> &stack,
                        std::vector<float> &values) {
  values.resize(static_cast<size_t>(frames));
  auto it = node.timelines.find(param);
  if (it == node.timelines.end()) {
    std::fill(values.begin(), values.end(), currentParam(node, param, fallback));
  } else {
    const float endValue = it->second->processBlock(
        blockStart, sampleRate.load(std::memory_order_relaxed), frames,
        values.data());
    node.paramValues[param] = endValue;
  }
  addParamInputBlock(node, param, stack, values);
}

void Engine::addParamInputBlock(Node &node, const char *param,
                                std::vector<int32_t> &stack,
                                std::vector<float> &values) {
  if (!param || values.empty()) {
    return;
  }

  for (const auto &connection : paramConnections) {
    if (connection.dst != node.id || connection.param != param) {
      continue;
    }

    const bool cycle = std::find(stack.begin(), stack.end(), connection.src) !=
                       stack.end();
    const AudioBus *srcBus = nullptr;
    if (cycle) {
      if (const auto *srcNode = findNodeUnlocked(connection.src)) {
        srcBus = &srcNode->previous;
      }
    } else {
      srcBus = &renderNode(connection.src, stack);
    }
    if (!srcBus || srcBus->frames <= 0 || srcBus->channels <= 0) {
      continue;
    }

    const int frames = std::min<int>(renderFrames, srcBus->frames);
    if (connection.output > 0) {
      const int srcCh = std::min(connection.output, srcBus->channels - 1);
      const float *src = srcBus->channel(srcCh);
      if (!src) {
        continue;
      }
      for (int i = 0; i < frames; ++i) {
        values[static_cast<size_t>(i)] += src[i];
      }
      continue;
    }

    const float scale = 1.0f / static_cast<float>(srcBus->channels);
    for (int ch = 0; ch < srcBus->channels; ++ch) {
      const float *src = srcBus->channel(ch);
      if (!src) {
        continue;
      }
      for (int i = 0; i < frames; ++i) {
        values[static_cast<size_t>(i)] += src[i] * scale;
      }
    }
  }
}

int32_t Engine::createGain() {
  Node node;
  node.kind = NodeKind::Gain;
  setDefaultParam(node, "gain", 1.0f);
  return addNode(std::move(node));
}

int32_t Engine::createOscillator() {
  Node node;
  node.kind = NodeKind::Oscillator;
  node.inputCount = 0;
  setDefaultParam(node, "frequency", 440.0f);
  setDefaultParam(node, "detune", 0.0f);
  return addNode(std::move(node));
}

int32_t Engine::createBiquadFilter() {
  Node node;
  node.kind = NodeKind::BiquadFilter;
  setDefaultParam(node, "frequency", 350.0f);
  setDefaultParam(node, "detune", 0.0f);
  setDefaultParam(node, "Q", 1.0f);
  setDefaultParam(node, "gain", 0.0f);
  node.biquad.resize(static_cast<size_t>(renderChannels));
  return addNode(std::move(node));
}

int32_t Engine::createCompressor() {
  Node node;
  node.kind = NodeKind::Compressor;
  setDefaultParam(node, "threshold", -24.0f);
  setDefaultParam(node, "knee", 30.0f);
  setDefaultParam(node, "ratio", 12.0f);
  setDefaultParam(node, "attack", 0.003f);
  setDefaultParam(node, "release", 0.25f);
  return addNode(std::move(node));
}

int32_t Engine::createDelay(float maxDelay) {
  Node node;
  node.kind = NodeKind::Delay;
  node.maxDelay = std::max(0.001f, maxDelay);
  setDefaultParam(node, "delayTime", 0.0f);
  setDefaultParam(node, "feedback", 0.0f);
  const int maxFrames =
      static_cast<int>(std::ceil(node.maxDelay * getSampleRate())) +
      bufferSize.load() + 8;
  node.delayLines.resize(static_cast<size_t>(renderChannels));
  for (auto &line : node.delayLines) {
    line.assign(static_cast<size_t>(std::max(1, maxFrames)), 0.0f);
  }
  return addNode(std::move(node));
}

int32_t Engine::createBufferSource() {
  Node node;
  node.kind = NodeKind::BufferSource;
  node.inputCount = 0;
  setDefaultParam(node, "playbackRate", 1.0f);
  setDefaultParam(node, "detune", 0.0f);
  setDefaultParam(node, "decay", kNeutralDecaySeconds);
  return addNode(std::move(node));
}

int32_t Engine::createAnalyser() {
  Node node;
  node.kind = NodeKind::Analyser;
  node.analyserTime.assign(2048, 0.0f);
  node.analyserPreviousDb.assign(1024, -100.0f);
  return addNode(std::move(node));
}

int32_t Engine::createStereoPanner() {
  Node node;
  node.kind = NodeKind::StereoPanner;
  setDefaultParam(node, "pan", 0.0f);
  return addNode(std::move(node));
}

int32_t Engine::createPanner() {
  Node node;
  node.kind = NodeKind::Panner;
  setDefaultParam(node, "positionX", 0.0f);
  setDefaultParam(node, "positionY", 0.0f);
  setDefaultParam(node, "positionZ", 0.0f);
  setDefaultParam(node, "orientationX", 1.0f);
  setDefaultParam(node, "orientationY", 0.0f);
  setDefaultParam(node, "orientationZ", 0.0f);
  return addNode(std::move(node));
}

int32_t Engine::createWaveShaper() {
  Node node;
  node.kind = NodeKind::WaveShaper;
  return addNode(std::move(node));
}

int32_t Engine::createConstantSource() {
  Node node;
  node.kind = NodeKind::ConstantSource;
  node.inputCount = 0;
  setDefaultParam(node, "offset", 1.0f);
  return addNode(std::move(node));
}

int32_t Engine::createConvolver() {
  Node node;
  node.kind = NodeKind::Convolver;
  return addNode(std::move(node));
}

int32_t Engine::createIIRFilter(const double *feedforward,
                                int32_t feedforwardLen,
                                const double *feedback,
                                int32_t feedbackLen) {
  if (!feedforward || !feedback || feedforwardLen <= 0 || feedbackLen <= 0 ||
      std::abs(feedback[0]) < 1.0e-12) {
    return -1;
  }
  Node node;
  node.kind = NodeKind::IIRFilter;
  node.iirFeedforward.assign(feedforward, feedforward + feedforwardLen);
  node.iirFeedback.assign(feedback, feedback + feedbackLen);
  return addNode(std::move(node));
}

int32_t Engine::createChannelSplitter(int32_t outputs) {
  Node node;
  node.kind = NodeKind::ChannelSplitter;
  node.outputCount = std::max<int32_t>(1, outputs);
  return addNode(std::move(node));
}

int32_t Engine::createChannelMerger(int32_t inputs) {
  Node node;
  node.kind = NodeKind::ChannelMerger;
  node.inputCount = std::max<int32_t>(1, inputs);
  return addNode(std::move(node));
}

int32_t Engine::createMediaStreamSource() {
  Node node;
  node.kind = NodeKind::MediaStreamSource;
  node.inputCount = 0;
  const int32_t id = addNode(std::move(node));
  requestMediaInput();
  return id;
}

int32_t Engine::createMediaStreamDestination() {
  Node node;
  node.kind = NodeKind::MediaStreamDestination;
  node.outputCount = 0;
  return addNode(std::move(node));
}

int32_t Engine::createWorkletBridge(int32_t inputs, int32_t outputs) {
  Node node;
  node.kind = NodeKind::WorkletBridge;
  node.inputCount = std::max<int32_t>(0, inputs);
  node.outputCount = std::max<int32_t>(1, outputs);
  const int capacity = std::max(2048, bufferSize.load() * 8);
  node.bridge = std::make_shared<WorkletBridgeState>();
  node.bridge->inputChannels = std::max<int32_t>(1, inputs);
  node.bridge->outputChannels = std::max<int32_t>(1, outputs);
  node.bridge->capacity = capacity;
  node.bridge->toIsolate = std::make_shared<MultiChannelSPSCRingBuffer>(
      node.bridge->inputChannels, capacity);
  node.bridge->fromIsolate = std::make_shared<MultiChannelSPSCRingBuffer>(
      node.bridge->outputChannels, capacity);
  node.workletLastOutput.assign(
      static_cast<size_t>(node.bridge->outputChannels), 0.0f);
  return addNode(std::move(node));
}

void Engine::createMachineVoice(int32_t *resultIds) {
  if (!resultIds) {
    return;
  }
  resultIds[0] = createOscillator();
  resultIds[1] = createBiquadFilter();
  resultIds[2] = createGain();
  resultIds[3] = createStereoPanner();
  resultIds[4] = createDelay(5.0f);
  resultIds[5] = createGain();
  resultIds[6] = createGain();
  paramSet(resultIds[1], "frequency", 2000.0f);
  paramSet(resultIds[1], "Q", 1.0f);
  paramSet(resultIds[2], "gain", 0.0f);
  paramSet(resultIds[4], "delayTime", 0.3f);
  paramSet(resultIds[5], "gain", 0.0f);
  paramSet(resultIds[6], "gain", 0.0f);
  oscStart(resultIds[0], 0.0);

  connect(resultIds[0], resultIds[1], 0, 0);
  connect(resultIds[1], resultIds[2], 0, 0);
  connect(resultIds[2], resultIds[3], 0, 0);
  connect(resultIds[3], resultIds[4], 0, 0);
  connect(resultIds[4], resultIds[6], 0, 0);
  connect(resultIds[4], resultIds[5], 0, 0);
  connect(resultIds[5], resultIds[4], 0, 0);

  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  const int32_t root = resultIds[0];
  std::vector<int32_t> ids(resultIds, resultIds + 7);
  auto active = std::make_shared<std::atomic<bool>>(false);
  machineVoiceGroups[root] = ids;
  for (auto id : ids) {
    machineVoiceRootByNode[id] = root;
    if (auto *node = findNodeUnlocked(id)) {
      node->machineActive = active;
    }
  }
  if (auto *node = findNodeUnlocked(resultIds[5])) {
    node->allowSilentInputSkip = true;
  }
  if (auto *node = findNodeUnlocked(resultIds[6])) {
    node->allowSilentInputSkip = true;
  }
  {
    std::lock_guard<std::mutex> activeLock(machineVoiceActiveMtx);
    for (auto id : ids) {
      machineVoiceActiveByNode[id] = active;
    }
  }
}

void Engine::removeNode(int32_t nodeId) {
  if (nodeId == 0) {
    return;
  }
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  std::vector<int32_t> idsToRemove{nodeId};
  auto rootIt = machineVoiceRootByNode.find(nodeId);
  if (rootIt != machineVoiceRootByNode.end()) {
    const int32_t root = rootIt->second;
    auto groupIt = machineVoiceGroups.find(root);
    if (groupIt != machineVoiceGroups.end()) {
      idsToRemove = groupIt->second;
    }
  }
  const std::unordered_set<int32_t> removeSet(idsToRemove.begin(),
                                              idsToRemove.end());
  connections.erase(std::remove_if(connections.begin(), connections.end(),
                                   [&removeSet](const Connection &c) {
                                     return removeSet.count(c.src) > 0 ||
                                            removeSet.count(c.dst) > 0;
                                   }),
                    connections.end());
  paramConnections.erase(
      std::remove_if(paramConnections.begin(), paramConnections.end(),
                     [&removeSet](const ParamConnection &c) {
                       return removeSet.count(c.src) > 0 ||
                              removeSet.count(c.dst) > 0;
                     }),
      paramConnections.end());
  for (auto id : idsToRemove) {
    nodes.erase(id);
  }
  for (auto id : idsToRemove) {
    auto it = machineVoiceRootByNode.find(id);
    if (it != machineVoiceRootByNode.end()) {
      machineVoiceGroups.erase(it->second);
      machineVoiceRootByNode.erase(it);
    }
  }
  {
    std::lock_guard<std::mutex> activeLock(machineVoiceActiveMtx);
    for (auto id : idsToRemove) {
      machineVoiceActiveByNode.erase(id);
    }
  }
}

void Engine::setMachineVoiceActive(int32_t nodeId, bool active) {
  std::shared_ptr<std::atomic<bool>> activeState;
  {
    std::lock_guard<std::mutex> activeLock(machineVoiceActiveMtx);
    auto it = machineVoiceActiveByNode.find(nodeId);
    if (it != machineVoiceActiveByNode.end()) {
      activeState = it->second;
    }
  }
  if (activeState) {
    activeState->store(active, std::memory_order_release);
  }
}

bool Engine::pathExistsUnlocked(int32_t from, int32_t to) const {
  if (from == to) {
    return true;
  }
  std::unordered_set<int32_t> seen;
  std::queue<int32_t> q;
  q.push(from);
  seen.insert(from);
  while (!q.empty()) {
    const int32_t current = q.front();
    q.pop();
    for (const auto &c : connections) {
      if (c.src != current || seen.count(c.dst) != 0) {
        continue;
      }
      if (c.dst == to) {
        return true;
      }
      seen.insert(c.dst);
      q.push(c.dst);
    }
  }
  return false;
}

void Engine::markFeedbackIfCycleUnlocked(int32_t src, int32_t dst) {
  if (pathExistsUnlocked(dst, src)) {
    feedbackCycleCount.fetch_add(1, std::memory_order_relaxed);
  }
}

void Engine::connect(int32_t srcId, int32_t dstId, int output, int input) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  const auto *src = findNodeUnlocked(srcId);
  const auto *dst = findNodeUnlocked(dstId);
  if (!src || !dst || output < 0 || input < 0 || output >= src->outputCount ||
      input >= dst->inputCount) {
    return;
  }
  for (const auto &connection : connections) {
    if (connection.src == srcId && connection.dst == dstId &&
        connection.output == output && connection.input == input) {
      return;
    }
  }
  markFeedbackIfCycleUnlocked(srcId, dstId);
  connections.push_back({srcId, dstId, output, input});
}

void Engine::connectParam(int32_t srcId, int32_t dstId, const char *param,
                          int output) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  const auto *src = findNodeUnlocked(srcId);
  const auto *dst = findNodeUnlocked(dstId);
  if (!src || !dst || !param || output < 0 || output >= src->outputCount ||
      dst->paramValues.find(param) == dst->paramValues.end()) {
    return;
  }
  for (const auto &connection : paramConnections) {
    if (connection.src == srcId && connection.dst == dstId &&
        connection.output == output && connection.param == param) {
      return;
    }
  }
  paramConnections.push_back({srcId, dstId, param, output});
}

void Engine::disconnect(int32_t srcId, int32_t dstId) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  connections.erase(std::remove_if(connections.begin(), connections.end(),
                                   [srcId, dstId](const Connection &c) {
                                     return c.src == srcId && c.dst == dstId;
                                   }),
                    connections.end());
  paramConnections.erase(
      std::remove_if(paramConnections.begin(), paramConnections.end(),
                     [srcId, dstId](const ParamConnection &c) {
                       return c.src == srcId && c.dst == dstId;
                     }),
      paramConnections.end());
}

void Engine::disconnectOutput(int32_t srcId, int output) {
  if (output < 0) {
    return;
  }
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  connections.erase(std::remove_if(connections.begin(), connections.end(),
                                   [srcId, output](const Connection &c) {
                                     return c.src == srcId &&
                                            c.output == output;
                                   }),
                    connections.end());
  paramConnections.erase(
      std::remove_if(paramConnections.begin(), paramConnections.end(),
                     [srcId, output](const ParamConnection &c) {
                       return c.src == srcId && c.output == output;
                     }),
      paramConnections.end());
}

void Engine::disconnectNodeOutput(int32_t srcId, int32_t dstId, int output) {
  if (output < 0) {
    return;
  }
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  connections.erase(std::remove_if(connections.begin(), connections.end(),
                                   [srcId, dstId, output](const Connection &c) {
                                     return c.src == srcId && c.dst == dstId &&
                                            c.output == output;
                                   }),
                    connections.end());
}

void Engine::disconnectNodeInput(int32_t srcId, int32_t dstId, int output,
                                 int input) {
  if (output < 0 || input < 0) {
    return;
  }
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  connections.erase(
      std::remove_if(connections.begin(), connections.end(),
                     [srcId, dstId, output, input](const Connection &c) {
                       return c.src == srcId && c.dst == dstId &&
                              c.output == output && c.input == input;
                     }),
      connections.end());
}

void Engine::disconnectParam(int32_t srcId, int32_t dstId, const char *param,
                             int output) {
  if (!param || output < 0) {
    return;
  }
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  paramConnections.erase(
      std::remove_if(paramConnections.begin(), paramConnections.end(),
                     [srcId, dstId, param, output](const ParamConnection &c) {
                       return c.src == srcId && c.dst == dstId &&
                              c.output == output && c.param == param;
                     }),
      paramConnections.end());
}

void Engine::disconnectAll(int32_t srcId) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  connections.erase(std::remove_if(connections.begin(), connections.end(),
                                   [srcId](const Connection &c) {
                                     return c.src == srcId;
                                   }),
                    connections.end());
  paramConnections.erase(
      std::remove_if(paramConnections.begin(), paramConnections.end(),
                     [srcId](const ParamConnection &c) {
                       return c.src == srcId;
                     }),
      paramConnections.end());
}

void Engine::paramSet(int32_t nodeId, const char *param, float value) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  if (auto *node = findNodeUnlocked(nodeId)) {
    node->paramValues[param] = value;
    timelineFor(*node, param).setLastValue(value);
  }
}

void Engine::paramSetAtTime(int32_t nodeId, const char *param, float value,
                            double time) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  if (auto *node = findNodeUnlocked(nodeId)) {
    node->paramValues[param] = value;
    timelineFor(*node, param).setValueAtTime(value, time);
  }
}

void Engine::paramLinearRamp(int32_t nodeId, const char *param, float value,
                             double endTime) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  if (auto *node = findNodeUnlocked(nodeId)) {
    node->paramValues[param] = value;
    timelineFor(*node, param).linearRampToValueAtTime(value, endTime);
  }
}

void Engine::paramExpRamp(int32_t nodeId, const char *param, float value,
                          double endTime) {
  if (value <= 0.0f) {
    return;
  }
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  if (auto *node = findNodeUnlocked(nodeId)) {
    node->paramValues[param] = value;
    timelineFor(*node, param).exponentialRampToValueAtTime(value, endTime);
  }
}

void Engine::paramSetTarget(int32_t nodeId, const char *param, float target,
                            double startTime, float tc) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  if (auto *node = findNodeUnlocked(nodeId)) {
    node->paramValues[param] = target;
    timelineFor(*node, param).setTargetAtTime(target, startTime, tc);
  }
}

void Engine::paramCancel(int32_t nodeId, const char *param,
                         double cancelTime) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  if (auto *node = findNodeUnlocked(nodeId)) {
    timelineFor(*node, param).cancelScheduledValues(cancelTime);
  }
}

void Engine::paramCancelAndHold(int32_t nodeId, const char *param,
                                double time) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  if (auto *node = findNodeUnlocked(nodeId)) {
    timelineFor(*node, param).cancelAndHoldAtTime(time, getSampleRate());
  }
}

void Engine::paramSetValueCurve(int32_t nodeId, const char *param,
                                const float *values, int32_t length,
                                double startTime, double duration) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  if (auto *node = findNodeUnlocked(nodeId)) {
    timelineFor(*node, param).setValueCurveAtTime(values, length, startTime,
                                                  duration);
    if (values && length > 0) {
      node->paramValues[param] = values[length - 1];
    }
  }
}

float Engine::paramGet(int32_t nodeId, const char *param) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  if (!param) {
    return 0.0f;
  }
  if (auto *node = findNodeUnlocked(nodeId)) {
    return currentParam(*node, param, 0.0f);
  }
  return 0.0f;
}

void Engine::oscSetType(int32_t nodeId, int type) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  if (auto *node = findNodeUnlocked(nodeId)) {
    node->oscillatorType = std::max(0, std::min(4, type));
  }
}

void Engine::oscStart(int32_t nodeId, double when) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  if (auto *node = findNodeUnlocked(nodeId)) {
    node->phase = 0.0;
    node->startTime = when;
  }
}

void Engine::oscStop(int32_t nodeId, double when) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  if (auto *node = findNodeUnlocked(nodeId)) {
    node->stopTime = when;
  }
}

void Engine::oscSetPeriodicWave(int32_t nodeId, const float *real,
                                const float *imag, int32_t len,
                                bool disableNormalization) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  auto *node = findNodeUnlocked(nodeId);
  if (!node || !real || !imag || len <= 0) {
    return;
  }
  const int tableSize = 2048;
  node->periodicWave.assign(tableSize, 0.0f);
  float maxAbs = 0.0f;
  for (int i = 0; i < tableSize; ++i) {
    const double phase = (2.0 * kPi * i) / tableSize;
    double value = 0.0;
    for (int k = 1; k < len; ++k) {
      value += real[k] * std::cos(phase * k) + imag[k] * std::sin(phase * k);
    }
    const float sample = std::isfinite(value) ? static_cast<float>(value) : 0.0f;
    node->periodicWave[static_cast<size_t>(i)] = sample;
    maxAbs = std::max(maxAbs, std::abs(sample));
  }
  if (!disableNormalization && maxAbs > kSilentFloor) {
    const float scale = 1.0f / maxAbs;
    for (auto &sample : node->periodicWave) {
      sample *= scale;
    }
  }
  node->oscillatorType = 4;
}

void Engine::filterSetType(int32_t nodeId, int type) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  if (auto *node = findNodeUnlocked(nodeId)) {
    node->filterType = std::max(0, std::min(7, type));
  }
}

void Engine::bufferSourceSetBuffer(int32_t nodeId, const float *data,
                                   int32_t frames, int32_t channels,
                                   int32_t sr) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  auto *node = findNodeUnlocked(nodeId);
  if (!node || !data || frames <= 0 || channels <= 0) {
    return;
  }
  node->sourceFrames = frames;
  node->sourceChannels = channels;
  node->sourceSampleRate = sr > 0 ? sr : static_cast<int32_t>(getSampleRate());
  node->sourceCursor = 0.0;
  node->sourceBuffer.assign(data, data + static_cast<size_t>(frames * channels));
}

void Engine::bufferSourceStart(int32_t nodeId, double when) {
  bufferSourceStart(nodeId, when, 0.0, 0.0, false);
}

void Engine::bufferSourceStart(int32_t nodeId, double when, double offset,
                               double duration, bool hasDuration) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  if (auto *node = findNodeUnlocked(nodeId)) {
    const double boundedOffset = std::max(0.0, offset);
    const double sourceSr =
        node->sourceSampleRate > 0 ? node->sourceSampleRate : getSampleRate();
    node->sourceOffset = boundedOffset;
    node->sourceDuration = std::max(0.0, duration);
    node->sourceHasDuration = hasDuration;
    node->sourceCursor = boundedOffset * sourceSr;
    node->sourceStartTime = when;
    node->sourceEnvelope = 1.0f;
  }
}

void Engine::bufferSourceStop(int32_t nodeId, double when) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  if (auto *node = findNodeUnlocked(nodeId)) {
    node->sourceStopTime = when;
  }
}

void Engine::bufferSourceSetLoop(int32_t nodeId, bool loop) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  if (auto *node = findNodeUnlocked(nodeId)) {
    node->sourceLoop = loop;
  }
}

void Engine::bufferSourceSetLoopPoints(int32_t nodeId, double loopStart,
                                       double loopEnd) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  if (auto *node = findNodeUnlocked(nodeId)) {
    node->sourceLoopStart = std::max(0.0, loopStart);
    node->sourceLoopEnd = std::max(0.0, loopEnd);
  }
}

void Engine::analyserSetFftSize(int32_t nodeId, int32_t size) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  auto *node = findNodeUnlocked(nodeId);
  if (!node) {
    return;
  }
  int fft = 32;
  while (fft < size && fft < 32768) {
    fft <<= 1;
  }
  node->analyserFftSize = fft;
  node->analyserTime.assign(static_cast<size_t>(fft), 0.0f);
  node->analyserPreviousDb.assign(static_cast<size_t>(fft / 2), -100.0f);
}

void Engine::analyserSetMinDecibels(int32_t nodeId, double value) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  if (auto *node = findNodeUnlocked(nodeId)) {
    node->analyserMinDecibels =
        std::min(static_cast<float>(value), node->analyserMaxDecibels - 0.001f);
  }
}

void Engine::analyserSetMaxDecibels(int32_t nodeId, double value) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  if (auto *node = findNodeUnlocked(nodeId)) {
    node->analyserMaxDecibels =
        std::max(static_cast<float>(value), node->analyserMinDecibels + 0.001f);
  }
}

void Engine::analyserSetSmoothingTimeConstant(int32_t nodeId, double value) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  if (auto *node = findNodeUnlocked(nodeId)) {
    node->analyserSmoothing =
        clampFloat(static_cast<float>(value), 0.0f, 1.0f);
  }
}

void Engine::waveShaperSetCurve(int32_t nodeId, const float *data,
                                int32_t len) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  auto *node = findNodeUnlocked(nodeId);
  if (!node || !data || len <= 0) {
    return;
  }
  node->waveShaperCurve.assign(data, data + len);
}

void Engine::waveShaperSetOversample(int32_t nodeId, int type) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  if (auto *node = findNodeUnlocked(nodeId)) {
    node->waveShaperOversample = std::max(0, std::min(2, type));
  }
}

void Engine::convolverSetNormalize(int32_t nodeId, bool normalize) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  if (auto *node = findNodeUnlocked(nodeId)) {
    node->convolverNormalize = normalize;
  }
}

void Engine::convolverSetBuffer(int32_t nodeId, const float *data,
                                int32_t frames, int32_t channels, int32_t sr,
                                bool normalize) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  auto *node = findNodeUnlocked(nodeId);
  if (!node) {
    return;
  }
  node->convolverNormalize = normalize;
  node->convolverHistory.clear();
  node->convolverWrite = 0;
  if (!data || frames <= 0 || channels <= 0) {
    node->convolverBuffer.clear();
    node->convolverFrames = 0;
    node->convolverChannels = 0;
    return;
  }
  node->convolverFrames = frames;
  node->convolverChannels = channels;
  node->convolverSampleRate = sr > 0 ? sr : static_cast<int32_t>(getSampleRate());
  node->convolverBuffer.assign(data, data + static_cast<size_t>(frames * channels));
  if (normalize) {
    double energy = 0.0;
    for (float sample : node->convolverBuffer) {
      energy += static_cast<double>(sample) * sample;
    }
    if (energy > kSilentFloor) {
      const float scale = static_cast<float>(1.0 / std::sqrt(energy));
      for (auto &sample : node->convolverBuffer) {
        sample *= scale;
      }
    }
  }
}

std::shared_ptr<WorkletBridgeState>
Engine::getWorkletBridgeState(int32_t nodeId) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  auto *node = findNodeUnlocked(nodeId);
  return node ? node->bridge : nullptr;
}

int32_t Engine::getWorkletBridgeInputChannelCount(int32_t nodeId) {
  auto state = getWorkletBridgeState(nodeId);
  return state ? state->inputChannels : 0;
}

int32_t Engine::getWorkletBridgeOutputChannelCount(int32_t nodeId) {
  auto state = getWorkletBridgeState(nodeId);
  return state ? state->outputChannels : 0;
}

int32_t Engine::getWorkletBridgeCapacity(int32_t nodeId) {
  auto state = getWorkletBridgeState(nodeId);
  return state ? state->capacity : 0;
}

void Engine::releaseWorkletBridge(int32_t nodeId) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  if (auto *node = findNodeUnlocked(nodeId); node && node->bridge) {
    node->bridge->active.store(false, std::memory_order_release);
    const auto dropped = node->bridge->droppedInputSamples.load(
        std::memory_order_relaxed);
    const auto underruns = node->bridge->outputUnderrunSamples.load(
        std::memory_order_relaxed);
    if (dropped > 0 || underruns > 0) {
      WA_LOG("WorkletBridge stats bridge=%d droppedIn=%lld underrunOut=%lld",
             nodeId, static_cast<long long>(dropped),
             static_cast<long long>(underruns));
    }
  }
}

void Engine::sumInputs(Node &node, std::vector<int32_t> &stack,
                       AudioBus &input) {
  input.resize(renderChannels, renderFrames);
  input.clear();

  for (const auto &connection : connections) {
    if (connection.dst != node.id) {
      continue;
    }
    const bool cycle = std::find(stack.begin(), stack.end(), connection.src) !=
                       stack.end();
    const AudioBus *srcBus = nullptr;
    if (cycle) {
      if (const auto *srcNode = findNodeUnlocked(connection.src)) {
        srcBus = &srcNode->previous;
      }
    } else {
      srcBus = &renderNode(connection.src, stack);
    }
    if (!srcBus || srcBus->frames <= 0) {
      continue;
    }

    if (node.kind == NodeKind::ChannelMerger || connection.output > 0 ||
        connection.input > 0) {
      const int srcCh = std::min(connection.output, srcBus->channels - 1);
      const int dstCh = std::min(connection.input, input.channels - 1);
      const float *src = srcBus->channel(srcCh);
      float *dst = input.channel(dstCh);
      if (!src || !dst) {
        continue;
      }
      for (int i = 0; i < renderFrames; ++i) {
        dst[i] += src[i];
      }
      continue;
    }

    const int channels = std::min(input.channels, srcBus->channels);
    for (int ch = 0; ch < channels; ++ch) {
      const float *src = srcBus->channel(ch);
      float *dst = input.channel(ch);
      for (int i = 0; i < renderFrames; ++i) {
        dst[i] += src[i];
      }
    }
  }
}

bool Engine::canSkipInactiveMachineNodeUnlocked(Node &node) const {
  return node.machineActive &&
         !node.machineActive->load(std::memory_order_acquire);
}

bool Engine::hasParamInputUnlocked(int32_t nodeId, const char *param) const {
  if (!param) {
    return false;
  }
  for (const auto &connection : paramConnections) {
    if (connection.dst == nodeId && connection.param == param) {
      return true;
    }
  }
  return false;
}

bool Engine::canSkipSilentGainUnlocked(Node &node) {
  if (!node.allowSilentInputSkip || node.kind != NodeKind::Gain ||
      hasParamInputUnlocked(node.id, "gain")) {
    return false;
  }
  auto it = node.timelines.find("gain");
  if (it == node.timelines.end() || !it->second) {
    return std::abs(currentParam(node, "gain", 1.0f)) <= 1.0e-7f;
  }
  return it->second->holdsValueForBlock(0.0f, renderBlockStartTime,
                                        getSampleRate(), renderFrames);
}

Engine::AudioBus &Engine::renderNode(int32_t nodeId,
                                     std::vector<int32_t> &stack) {
  auto *node = findNodeUnlocked(nodeId);
  if (!node) {
    return nodes[0].current;
  }
  if (node->renderSerial == renderSerial) {
    return node->current;
  }
  node->renderSerial = renderSerial;
  node->current.resize(renderChannels, renderFrames);
  node->current.clear();
  if (canSkipInactiveMachineNodeUnlocked(*node) ||
      canSkipSilentGainUnlocked(*node)) {
    return node->current;
  }

  stack.push_back(nodeId);
  AudioBus input;
  if (node->inputCount > 0 || node->kind == NodeKind::Destination) {
    sumInputs(*node, stack, input);
  }
  processNode(*node, input, stack);
  stack.pop_back();
  return node->current;
}

void Engine::processNode(Node &node, const AudioBus &input,
                         std::vector<int32_t> &stack) {
  switch (node.kind) {
  case NodeKind::Listener:
    node.current.resize(renderChannels, renderFrames);
    node.current.clear();
    break;
  case NodeKind::Destination:
  case NodeKind::ChannelSplitter:
  case NodeKind::ChannelMerger:
  case NodeKind::MediaStreamDestination:
    node.current = input;
    break;
  case NodeKind::Gain:
    node.current = input;
    paramBlock(node, "gain", 1.0f, renderBlockStartTime, renderFrames,
               stack, scratchParam);
    for (int ch = 0; ch < node.current.channels; ++ch) {
      float *out = node.current.channel(ch);
      for (int i = 0; i < renderFrames; ++i) {
        out[i] *= scratchParam[static_cast<size_t>(i)];
      }
    }
    break;
  case NodeKind::Oscillator:
    renderOscillator(node, stack);
    break;
  case NodeKind::ConstantSource:
    renderConstantSource(node, stack);
    break;
  case NodeKind::BiquadFilter:
    renderBiquad(node, input, stack);
    break;
  case NodeKind::IIRFilter:
    renderIIRFilter(node, input);
    break;
  case NodeKind::Compressor:
    renderCompressor(node, input, stack);
    break;
  case NodeKind::Delay:
    renderDelay(node, input, stack);
    break;
  case NodeKind::BufferSource:
    renderBufferSource(node, stack);
    break;
  case NodeKind::Analyser:
    renderAnalyser(node, input);
    break;
  case NodeKind::StereoPanner:
    renderStereoPanner(node, input, stack);
    break;
  case NodeKind::Panner:
    renderPanner(node, input, stack);
    break;
  case NodeKind::WaveShaper:
    renderWaveShaper(node, input);
    break;
  case NodeKind::Convolver:
    renderConvolver(node, input);
    break;
  case NodeKind::MediaStreamSource:
    renderMediaStreamSource(node);
    break;
  case NodeKind::WorkletBridge:
    renderWorklet(node, input);
    break;
  }
}

void Engine::copyCurrentToPrevious() {
  for (auto &[_, node] : nodes) {
    node.previous = node.current;
  }
}

void Engine::renderConstantSource(Node &node, std::vector<int32_t> &stack) {
  node.current.resize(renderChannels, renderFrames);
  node.current.clear();
  std::vector<float> offset;
  paramBlock(node, "offset", 1.0f, renderBlockStartTime, renderFrames, stack,
             offset);

  const double sr = getSampleRate();
  for (int i = 0; i < renderFrames; ++i) {
    const double t = renderBlockStartTime + static_cast<double>(i) / sr;
    if (node.startTime < 0.0 || t < node.startTime || t >= node.stopTime) {
      continue;
    }
    const float sample = offset[static_cast<size_t>(i)];
    for (int ch = 0; ch < node.current.channels; ++ch) {
      node.current.channel(ch)[i] = sample;
    }
  }
}

void Engine::renderOscillator(Node &node, std::vector<int32_t> &stack) {
  node.current.resize(renderChannels, renderFrames);
  node.current.clear();
  std::vector<float> freq;
  std::vector<float> detune;
  paramBlock(node, "frequency", 440.0f, renderBlockStartTime, renderFrames,
             stack, freq);
  paramBlock(node, "detune", 0.0f, renderBlockStartTime, renderFrames, stack,
             detune);

  const double sr = getSampleRate();
  for (int i = 0; i < renderFrames; ++i) {
    const double t = renderBlockStartTime + static_cast<double>(i) / sr;
    if (node.startTime < 0.0 || t < node.startTime || t >= node.stopTime) {
      continue;
    }

    float sample = 0.0f;
    switch (node.oscillatorType) {
    case 0:
      sample = static_cast<float>(std::sin(node.phase * 2.0 * kPi));
      break;
    case 1:
      sample = node.phase < 0.5 ? 1.0f : -1.0f;
      break;
    case 2:
      sample = node.phase < 0.5 ? static_cast<float>(2.0 * node.phase)
                                : static_cast<float>(2.0 * node.phase - 2.0);
      break;
    case 3:
      if (node.phase < 0.25) {
        sample = static_cast<float>(4.0 * node.phase);
      } else if (node.phase < 0.75) {
        sample = static_cast<float>(2.0 - 4.0 * node.phase);
      } else {
        sample = static_cast<float>(4.0 * node.phase - 4.0);
      }
      break;
    case 4:
      if (!node.periodicWave.empty()) {
        const double idx = node.phase * node.periodicWave.size();
        const auto i0 = static_cast<size_t>(idx) % node.periodicWave.size();
        const auto i1 = (i0 + 1) % node.periodicWave.size();
        const float frac = static_cast<float>(idx - std::floor(idx));
        sample = node.periodicWave[i0] +
                 frac * (node.periodicWave[i1] - node.periodicWave[i0]);
      }
      break;
    }

    for (int ch = 0; ch < node.current.channels; ++ch) {
      node.current.channel(ch)[i] = sample;
    }

    const float actualFreq =
        freq[static_cast<size_t>(i)] *
        std::pow(2.0f, detune[static_cast<size_t>(i)] / 1200.0f);
    node.phase += actualFreq / sr;
    node.phase -= std::floor(node.phase);
  }
}

void Engine::renderBufferSource(Node &node, std::vector<int32_t> &stack) {
  node.current.resize(renderChannels, renderFrames);
  node.current.clear();
  if (node.sourceBuffer.empty() || node.sourceFrames <= 0 ||
      node.sourceChannels <= 0) {
    return;
  }

  std::vector<float> rateValues;
  std::vector<float> detuneValues;
  std::vector<float> decayValues;
  paramBlock(node, "playbackRate", 1.0f, renderBlockStartTime, renderFrames,
             stack, rateValues);
  paramBlock(node, "detune", 0.0f, renderBlockStartTime, renderFrames,
             stack, detuneValues);
  paramBlock(node, "decay", kNeutralDecaySeconds, renderBlockStartTime,
             renderFrames, stack, decayValues);

  const double sr = getSampleRate();
  const double sourceSr =
      node.sourceSampleRate > 0 ? node.sourceSampleRate : getSampleRate();
  int loopStartFrame =
      static_cast<int>(std::floor(std::max(0.0, node.sourceLoopStart) * sourceSr));
  int loopEndFrame = node.sourceLoopEnd > 0.0
                         ? static_cast<int>(std::floor(node.sourceLoopEnd *
                                                       sourceSr))
                         : node.sourceFrames;
  loopStartFrame = std::max(0, std::min(loopStartFrame, node.sourceFrames - 1));
  loopEndFrame = std::max(loopStartFrame + 1,
                          std::min(loopEndFrame, node.sourceFrames));

  for (int i = 0; i < renderFrames; ++i) {
    const double t = renderBlockStartTime + static_cast<double>(i) / sr;
    if (node.sourceStartTime < 0.0 || t < node.sourceStartTime ||
        t >= node.sourceStopTime ||
        (node.sourceHasDuration && t >= node.sourceStartTime + node.sourceDuration)) {
      continue;
    }
    int frame = static_cast<int>(node.sourceCursor);
    const int playableEnd = node.sourceLoop ? loopEndFrame : node.sourceFrames;
    if (frame >= playableEnd) {
      if (!node.sourceLoop) {
        continue;
      }
      const double loopLen = std::max(1, loopEndFrame - loopStartFrame);
      node.sourceCursor =
          loopStartFrame + std::fmod(node.sourceCursor - loopStartFrame, loopLen);
      frame = static_cast<int>(node.sourceCursor);
    }
    const int nextFrame = node.sourceLoop
                              ? (frame + 1 >= loopEndFrame ? loopStartFrame
                                                           : frame + 1)
                              : std::min(frame + 1, node.sourceFrames - 1);
    const float frac = static_cast<float>(node.sourceCursor - frame);
    for (int ch = 0; ch < node.current.channels; ++ch) {
      const int srcCh = std::min(ch, node.sourceChannels - 1);
      const auto base = static_cast<size_t>(srcCh * node.sourceFrames);
      const float a = node.sourceBuffer[base + frame];
      const float b = node.sourceBuffer[base + nextFrame];
      node.current.channel(ch)[i] = (a + frac * (b - a)) * node.sourceEnvelope;
    }
    const double step =
        (sourceSr / sr) *
        rateValues[static_cast<size_t>(i)] *
        std::pow(2.0, detuneValues[static_cast<size_t>(i)] / 1200.0);
    node.sourceCursor += step;
    const float decaySeconds =
        std::max(0.001f, decayValues[static_cast<size_t>(i)]);
    node.sourceEnvelope *=
        static_cast<float>(std::exp(-1.0 / (decaySeconds * sr)));
  }
}

struct BiquadCoefficients {
  float b0 = 1.0f;
  float b1 = 0.0f;
  float b2 = 0.0f;
  float a1 = 0.0f;
  float a2 = 0.0f;
};

static BiquadCoefficients makeBiquad(int type, float frequency, float q,
                                     float gainDb, double sr) {
  const float nyquist = static_cast<float>(sr * 0.5);
  const float f = clampFloat(frequency, 1.0f, nyquist * 0.999f);
  const float omega = static_cast<float>(2.0 * kPi * f / sr);
  const float sinW = std::sin(omega);
  const float cosW = std::cos(omega);
  const float safeQ = std::max(0.0001f, std::abs(q));
  const float alpha = sinW / (2.0f * safeQ);
  const float a = std::pow(10.0f, gainDb / 40.0f);

  float b0 = 1.0f;
  float b1 = 0.0f;
  float b2 = 0.0f;
  float a0 = 1.0f;
  float a1 = 0.0f;
  float a2 = 0.0f;

  switch (type) {
  case 1:
    b0 = (1.0f + cosW) * 0.5f;
    b1 = -(1.0f + cosW);
    b2 = (1.0f + cosW) * 0.5f;
    a0 = 1.0f + alpha;
    a1 = -2.0f * cosW;
    a2 = 1.0f - alpha;
    break;
  case 2:
    b0 = alpha;
    b1 = 0.0f;
    b2 = -alpha;
    a0 = 1.0f + alpha;
    a1 = -2.0f * cosW;
    a2 = 1.0f - alpha;
    break;
  case 3: {
    const float sqrtA = std::sqrt(a);
    const float shelfAlpha = sinW / 2.0f * std::sqrt(2.0f);
    b0 = a * ((a + 1.0f) - (a - 1.0f) * cosW + 2.0f * sqrtA * shelfAlpha);
    b1 = 2.0f * a * ((a - 1.0f) - (a + 1.0f) * cosW);
    b2 = a * ((a + 1.0f) - (a - 1.0f) * cosW - 2.0f * sqrtA * shelfAlpha);
    a0 = (a + 1.0f) + (a - 1.0f) * cosW + 2.0f * sqrtA * shelfAlpha;
    a1 = -2.0f * ((a - 1.0f) + (a + 1.0f) * cosW);
    a2 = (a + 1.0f) + (a - 1.0f) * cosW - 2.0f * sqrtA * shelfAlpha;
    break;
  }
  case 4: {
    const float sqrtA = std::sqrt(a);
    const float shelfAlpha = sinW / 2.0f * std::sqrt(2.0f);
    b0 = a * ((a + 1.0f) + (a - 1.0f) * cosW + 2.0f * sqrtA * shelfAlpha);
    b1 = -2.0f * a * ((a - 1.0f) + (a + 1.0f) * cosW);
    b2 = a * ((a + 1.0f) + (a - 1.0f) * cosW - 2.0f * sqrtA * shelfAlpha);
    a0 = (a + 1.0f) - (a - 1.0f) * cosW + 2.0f * sqrtA * shelfAlpha;
    a1 = 2.0f * ((a - 1.0f) - (a + 1.0f) * cosW);
    a2 = (a + 1.0f) - (a - 1.0f) * cosW - 2.0f * sqrtA * shelfAlpha;
    break;
  }
  case 5:
    b0 = 1.0f + alpha * a;
    b1 = -2.0f * cosW;
    b2 = 1.0f - alpha * a;
    a0 = 1.0f + alpha / a;
    a1 = -2.0f * cosW;
    a2 = 1.0f - alpha / a;
    break;
  case 6:
    b0 = 1.0f;
    b1 = -2.0f * cosW;
    b2 = 1.0f;
    a0 = 1.0f + alpha;
    a1 = -2.0f * cosW;
    a2 = 1.0f - alpha;
    break;
  case 7:
    b0 = 1.0f - alpha;
    b1 = -2.0f * cosW;
    b2 = 1.0f + alpha;
    a0 = 1.0f + alpha;
    a1 = -2.0f * cosW;
    a2 = 1.0f - alpha;
    break;
  default:
    b0 = (1.0f - cosW) * 0.5f;
    b1 = 1.0f - cosW;
    b2 = (1.0f - cosW) * 0.5f;
    a0 = 1.0f + alpha;
    a1 = -2.0f * cosW;
    a2 = 1.0f - alpha;
    break;
  }

  if (std::abs(a0) < kSilentFloor) {
    return {};
  }
  return {b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0};
}

void Engine::renderBiquad(Node &node, const AudioBus &input,
                          std::vector<int32_t> &stack) {
  node.current = input;
  if (node.biquad.size() < static_cast<size_t>(node.current.channels)) {
    node.biquad.resize(static_cast<size_t>(node.current.channels));
  }

  std::vector<float> freqValues;
  std::vector<float> detuneValues;
  std::vector<float> qValues;
  std::vector<float> gainValues;
  paramBlock(node, "frequency", 350.0f, renderBlockStartTime, renderFrames,
             stack, freqValues);
  paramBlock(node, "detune", 0.0f, renderBlockStartTime, renderFrames,
             stack, detuneValues);
  paramBlock(node, "Q", 1.0f, renderBlockStartTime, renderFrames, stack,
             qValues);
  paramBlock(node, "gain", 0.0f, renderBlockStartTime, renderFrames,
             stack, gainValues);

  for (int ch = 0; ch < node.current.channels; ++ch) {
    auto &state = node.biquad[static_cast<size_t>(ch)];
    float *out = node.current.channel(ch);
    for (int i = 0; i < renderFrames; ++i) {
      const float f =
          freqValues[static_cast<size_t>(i)] *
          std::pow(2.0f, detuneValues[static_cast<size_t>(i)] / 1200.0f);
      const auto c = makeBiquad(node.filterType, f, qValues[i], gainValues[i],
                                getSampleRate());
      const float x = out[i];
      const float y = c.b0 * x + c.b1 * state.x1 + c.b2 * state.x2 -
                      c.a1 * state.y1 - c.a2 * state.y2;
      state.x2 = state.x1;
      state.x1 = x;
      state.y2 = state.y1;
      state.y1 = y;
      out[i] = std::isfinite(y) ? y : 0.0f;
    }
  }
}

void Engine::renderIIRFilter(Node &node, const AudioBus &input) {
  node.current.resize(renderChannels, renderFrames);
  node.current.clear();
  if (node.iirFeedforward.empty() || node.iirFeedback.empty() ||
      std::abs(node.iirFeedback[0]) < 1.0e-12) {
    node.current = input;
    return;
  }

  const int ffLen = static_cast<int>(node.iirFeedforward.size());
  const int fbLen = static_cast<int>(node.iirFeedback.size());
  if (node.iirInputHistory.size() < static_cast<size_t>(renderChannels)) {
    node.iirInputHistory.resize(static_cast<size_t>(renderChannels));
    node.iirOutputHistory.resize(static_cast<size_t>(renderChannels));
  }
  for (int ch = 0; ch < renderChannels; ++ch) {
    auto &xHist = node.iirInputHistory[static_cast<size_t>(ch)];
    auto &yHist = node.iirOutputHistory[static_cast<size_t>(ch)];
    xHist.resize(static_cast<size_t>(std::max(1, ffLen)), 0.0f);
    yHist.resize(static_cast<size_t>(std::max(1, fbLen)), 0.0f);
    float *out = node.current.channel(ch);
    const float *in = ch < input.channels ? input.channel(ch) : nullptr;
    for (int i = 0; i < renderFrames; ++i) {
      for (int k = ffLen - 1; k > 0; --k) {
        xHist[static_cast<size_t>(k)] = xHist[static_cast<size_t>(k - 1)];
      }
      xHist[0] = in ? in[i] : 0.0f;

      double y = 0.0;
      for (int k = 0; k < ffLen; ++k) {
        y += node.iirFeedforward[static_cast<size_t>(k)] *
             xHist[static_cast<size_t>(k)];
      }
      for (int k = 1; k < fbLen; ++k) {
        y -= node.iirFeedback[static_cast<size_t>(k)] *
             yHist[static_cast<size_t>(k - 1)];
      }
      y /= node.iirFeedback[0];
      const float sample = std::isfinite(y) ? static_cast<float>(y) : 0.0f;

      for (int k = fbLen - 1; k > 1; --k) {
        yHist[static_cast<size_t>(k - 1)] =
            yHist[static_cast<size_t>(k - 2)];
      }
      if (fbLen > 1) {
        yHist[0] = sample;
      }
      out[i] = sample;
    }
  }
}

void Engine::renderDelay(Node &node, const AudioBus &input,
                         std::vector<int32_t> &stack) {
  node.current.resize(renderChannels, renderFrames);
  node.current.clear();
  if (node.delayLines.size() < static_cast<size_t>(renderChannels)) {
    node.delayLines.resize(static_cast<size_t>(renderChannels));
  }
  const int maxDelayFrames =
      static_cast<int>(std::ceil(node.maxDelay * getSampleRate())) +
      bufferSize.load() + 8;
  for (auto &line : node.delayLines) {
    if (line.empty()) {
      line.assign(static_cast<size_t>(maxDelayFrames), 0.0f);
    }
  }

  std::vector<float> delayValues;
  std::vector<float> feedbackValues;
  paramBlock(node, "delayTime", 0.0f, renderBlockStartTime, renderFrames,
             stack, delayValues);
  paramBlock(node, "feedback", 0.0f, renderBlockStartTime, renderFrames,
             stack, feedbackValues);

  for (int i = 0; i < renderFrames; ++i) {
    for (int ch = 0; ch < renderChannels; ++ch) {
      auto &line = node.delayLines[static_cast<size_t>(ch)];
      const int lineSize = static_cast<int>(line.size());
      const float in = ch < input.channels ? input.channel(ch)[i] : 0.0f;
      const float delayFrames = clampFloat(delayValues[static_cast<size_t>(i)],
                                           0.0f, node.maxDelay) *
                                static_cast<float>(getSampleRate());
      float readPos = static_cast<float>(node.delayWrite) - delayFrames;
      while (readPos < 0.0f) {
        readPos += static_cast<float>(lineSize);
      }
      while (readPos >= lineSize) {
        readPos -= static_cast<float>(lineSize);
      }
      const int i0 = static_cast<int>(readPos);
      const int i1 = (i0 + 1) % lineSize;
      const float frac = readPos - static_cast<float>(i0);
      const float delayed =
          line[static_cast<size_t>(i0)] +
          frac * (line[static_cast<size_t>(i1)] - line[static_cast<size_t>(i0)]);
      const float fb =
          clampFloat(feedbackValues[static_cast<size_t>(i)], 0.0f, 0.9995f);
      node.current.channel(ch)[i] = delayed;
      line[static_cast<size_t>(node.delayWrite)] = in + delayed * fb;
    }
    if (!node.delayLines.empty()) {
      node.delayWrite = (node.delayWrite + 1) %
                        static_cast<int>(node.delayLines.front().size());
    }
  }
}

void Engine::renderCompressor(Node &node, const AudioBus &input,
                              std::vector<int32_t> &stack) {
  node.current = input;
  std::vector<float> thresholdValues;
  std::vector<float> kneeValues;
  std::vector<float> ratioValues;
  std::vector<float> attackValues;
  std::vector<float> releaseValues;
  paramBlock(node, "threshold", -24.0f, renderBlockStartTime, renderFrames,
             stack, thresholdValues);
  paramBlock(node, "knee", 30.0f, renderBlockStartTime, renderFrames, stack,
             kneeValues);
  paramBlock(node, "ratio", 12.0f, renderBlockStartTime, renderFrames, stack,
             ratioValues);
  paramBlock(node, "attack", 0.003f, renderBlockStartTime, renderFrames, stack,
             attackValues);
  paramBlock(node, "release", 0.25f, renderBlockStartTime, renderFrames, stack,
             releaseValues);
  float reduction = 0.0f;
  for (int ch = 0; ch < node.current.channels; ++ch) {
    float *out = node.current.channel(ch);
    for (int i = 0; i < renderFrames; ++i) {
      const auto index = static_cast<size_t>(i);
      const float threshold = thresholdValues[index];
      const float knee = std::max(0.0f, kneeValues[index]);
      const float ratio = std::max(1.0f, ratioValues[index]);
      const float attack = std::max(0.0001f, attackValues[index]);
      const float release = std::max(0.0001f, releaseValues[index]);
      const float attackCoeff =
          static_cast<float>(std::exp(-1.0 / (attack * getSampleRate())));
      const float releaseCoeff =
          static_cast<float>(std::exp(-1.0 / (release * getSampleRate())));
      const float absIn = std::max(std::abs(out[i]), kSilentFloor);
      const float db = 20.0f * std::log10(absIn);
      float targetReduction = 0.0f;
      if (knee > 0.0f && db > threshold - knee * 0.5f &&
          db < threshold + knee * 0.5f) {
        const float x = db - threshold + knee * 0.5f;
        targetReduction = (1.0f / ratio - 1.0f) * x * x / (2.0f * knee);
      } else if (db >= threshold + knee * 0.5f) {
        const float compressed = threshold + (db - threshold) / ratio;
        targetReduction = compressed - db;
      }
      const float coeff =
          targetReduction < node.compressorEnvelope ? attackCoeff : releaseCoeff;
      node.compressorEnvelope =
          coeff * node.compressorEnvelope + (1.0f - coeff) * targetReduction;
      out[i] *= decibelsToGain(node.compressorEnvelope);
      reduction = std::min(reduction, node.compressorEnvelope);
    }
  }
  node.compressorReduction = reduction;
}

void Engine::renderStereoPanner(Node &node, const AudioBus &input,
                                std::vector<int32_t> &stack) {
  node.current.resize(renderChannels, renderFrames);
  node.current.clear();
  std::vector<float> panValues;
  paramBlock(node, "pan", 0.0f, renderBlockStartTime, renderFrames, stack,
             panValues);
  for (int i = 0; i < renderFrames; ++i) {
    const float mono = input.channels > 1
                           ? 0.5f * (input.channel(0)[i] + input.channel(1)[i])
                           : (input.channels > 0 ? input.channel(0)[i] : 0.0f);
    const float pan = clampFloat(panValues[static_cast<size_t>(i)], -1.0f, 1.0f);
    const float angle = (pan + 1.0f) * static_cast<float>(kPi * 0.25);
    if (renderChannels == 1) {
      node.current.channel(0)[i] = mono;
    } else {
      node.current.channel(0)[i] = mono * std::cos(angle);
      node.current.channel(1)[i] = mono * std::sin(angle);
      for (int ch = 2; ch < renderChannels; ++ch) {
        node.current.channel(ch)[i] =
            ch < input.channels ? input.channel(ch)[i] : 0.0f;
      }
    }
  }
}

static float distanceGainForModel(int model, float distance, float refDistance,
                                  float maxDistance, float rolloff) {
  const float ref = std::max(0.0001f, refDistance);
  const float maxD = std::max(ref, maxDistance);
  const float d = clampFloat(distance, ref, maxD);
  switch (model) {
  case 0:
    if (maxD <= ref) {
      return 1.0f;
    }
    return clampFloat(1.0f - rolloff * (d - ref) / (maxD - ref), 0.0f, 1.0f);
  case 2:
    return clampFloat(std::pow(d / ref, -rolloff), 0.0f, 1.0f);
  case 1:
  default:
    return clampFloat(ref / (ref + rolloff * (d - ref)), 0.0f, 1.0f);
  }
}

static float coneGain(float orientX, float orientY, float orientZ, float toX,
                      float toY, float toZ, float innerAngle, float outerAngle,
                      float outerGain) {
  if (innerAngle >= 360.0f && outerAngle >= 360.0f) {
    return 1.0f;
  }
  const float orientLen =
      std::sqrt(orientX * orientX + orientY * orientY + orientZ * orientZ);
  const float toLen = std::sqrt(toX * toX + toY * toY + toZ * toZ);
  if (orientLen < kSilentFloor || toLen < kSilentFloor) {
    return 1.0f;
  }
  const float dot = (orientX * toX + orientY * toY + orientZ * toZ) /
                    (orientLen * toLen);
  const float angle =
      static_cast<float>(std::acos(clampFloat(dot, -1.0f, 1.0f)) * 180.0 / kPi);
  const float inner = clampFloat(innerAngle, 0.0f, 360.0f) * 0.5f;
  const float outer = clampFloat(std::max(innerAngle, outerAngle), 0.0f, 360.0f) *
                      0.5f;
  if (angle <= inner) {
    return 1.0f;
  }
  if (angle >= outer || outer <= inner) {
    return outerGain;
  }
  const float x = (angle - inner) / (outer - inner);
  return 1.0f + x * (outerGain - 1.0f);
}

void Engine::renderPanner(Node &node, const AudioBus &input,
                          std::vector<int32_t> &stack) {
  node.current.resize(renderChannels, renderFrames);
  node.current.clear();
  if (renderChannels == 1) {
    node.current = input;
    return;
  }

  Node *listener = findNodeUnlocked(listenerNodeId);
  std::vector<float> posX, posY, posZ, oriX, oriY, oriZ;
  std::vector<float> lisX, lisY, lisZ;
  paramBlock(node, "positionX", 0.0f, renderBlockStartTime, renderFrames,
             stack, posX);
  paramBlock(node, "positionY", 0.0f, renderBlockStartTime, renderFrames,
             stack, posY);
  paramBlock(node, "positionZ", 0.0f, renderBlockStartTime, renderFrames,
             stack, posZ);
  paramBlock(node, "orientationX", 1.0f, renderBlockStartTime, renderFrames,
             stack, oriX);
  paramBlock(node, "orientationY", 0.0f, renderBlockStartTime, renderFrames,
             stack, oriY);
  paramBlock(node, "orientationZ", 0.0f, renderBlockStartTime, renderFrames,
             stack, oriZ);
  if (listener) {
    paramBlock(*listener, "positionX", 0.0f, renderBlockStartTime, renderFrames,
               stack, lisX);
    paramBlock(*listener, "positionY", 0.0f, renderBlockStartTime, renderFrames,
               stack, lisY);
    paramBlock(*listener, "positionZ", 0.0f, renderBlockStartTime, renderFrames,
               stack, lisZ);
  } else {
    lisX.assign(static_cast<size_t>(renderFrames), 0.0f);
    lisY.assign(static_cast<size_t>(renderFrames), 0.0f);
    lisZ.assign(static_cast<size_t>(renderFrames), 0.0f);
  }

  for (int i = 0; i < renderFrames; ++i) {
    const float lx = lisX[static_cast<size_t>(i)];
    const float ly = lisY[static_cast<size_t>(i)];
    const float lz = lisZ[static_cast<size_t>(i)];
    const float sx = posX[static_cast<size_t>(i)];
    const float sy = posY[static_cast<size_t>(i)];
    const float sz = posZ[static_cast<size_t>(i)];
    const float relX = sx - lx;
    const float relY = sy - ly;
    const float relZ = sz - lz;
    const float distance =
        std::sqrt(relX * relX + relY * relY + relZ * relZ);
    const float horizontal = std::sqrt(relX * relX + relZ * relZ);
    const float pan = horizontal > kSilentFloor ? clampFloat(relX / horizontal,
                                                             -1.0f, 1.0f)
                                                : 0.0f;
    const float angle = (pan + 1.0f) * static_cast<float>(kPi * 0.25);
    const float distanceGain = distanceGainForModel(
        node.distanceModel, distance, node.refDistance, node.maxDistance,
        node.rolloffFactor);
    const float cone = coneGain(oriX[static_cast<size_t>(i)],
                                oriY[static_cast<size_t>(i)],
                                oriZ[static_cast<size_t>(i)], lx - sx, ly - sy,
                                lz - sz, node.coneInnerAngle,
                                node.coneOuterAngle, node.coneOuterGain);
    const float gain = distanceGain * cone;
    const float mono = input.channels > 1
                           ? 0.5f * (input.channel(0)[i] + input.channel(1)[i])
                           : (input.channels > 0 ? input.channel(0)[i] : 0.0f);
    node.current.channel(0)[i] = mono * std::cos(angle) * gain;
    node.current.channel(1)[i] = mono * std::sin(angle) * gain;
    for (int ch = 2; ch < renderChannels; ++ch) {
      node.current.channel(ch)[i] = mono * gain;
    }
  }
}

static float shapeWithCurve(const std::vector<float> &curve, float sample) {
  if (curve.empty()) {
    return sample;
  }
  const int len = static_cast<int>(curve.size());
  const float x = clampFloat(sample, -1.0f, 1.0f);
  const float idx = (x + 1.0f) * 0.5f * (len - 1);
  const int i0 = std::max(0, std::min(len - 1, static_cast<int>(idx)));
  const int i1 = std::min(len - 1, i0 + 1);
  const float frac = idx - i0;
  return curve[static_cast<size_t>(i0)] +
         frac * (curve[static_cast<size_t>(i1)] - curve[static_cast<size_t>(i0)]);
}

void Engine::renderWaveShaper(Node &node, const AudioBus &input) {
  node.current = input;
  if (node.waveShaperCurve.empty()) {
    return;
  }
  const int factor = node.waveShaperOversample == 1
                         ? 2
                         : (node.waveShaperOversample == 2 ? 4 : 1);
  for (int ch = 0; ch < node.current.channels; ++ch) {
    float *out = node.current.channel(ch);
    for (int i = 0; i < renderFrames; ++i) {
      if (factor == 1 || i + 1 >= renderFrames) {
        out[i] = shapeWithCurve(node.waveShaperCurve, out[i]);
        continue;
      }
      const float a = out[i];
      const float b = out[i + 1];
      double accum = 0.0;
      for (int sub = 0; sub < factor; ++sub) {
        const float t = static_cast<float>(sub) / factor;
        accum += shapeWithCurve(node.waveShaperCurve, a + t * (b - a));
      }
      out[i] = static_cast<float>(accum / factor);
    }
  }
}

void Engine::renderConvolver(Node &node, const AudioBus &input) {
  node.current.resize(renderChannels, renderFrames);
  node.current.clear();
  if (node.convolverBuffer.empty() || node.convolverFrames <= 0 ||
      node.convolverChannels <= 0) {
    return;
  }
  if (node.convolverHistory.size() < static_cast<size_t>(renderChannels)) {
    node.convolverHistory.resize(static_cast<size_t>(renderChannels));
  }
  for (auto &history : node.convolverHistory) {
    if (static_cast<int>(history.size()) != node.convolverFrames) {
      history.assign(static_cast<size_t>(node.convolverFrames), 0.0f);
    }
  }

  for (int i = 0; i < renderFrames; ++i) {
    for (int ch = 0; ch < renderChannels; ++ch) {
      auto &history = node.convolverHistory[static_cast<size_t>(ch)];
      const int inputCh = input.channels == 1 ? 0 : std::min(ch, input.channels - 1);
      history[static_cast<size_t>(node.convolverWrite)] =
          input.channels > 0 ? input.channel(inputCh)[i] : 0.0f;

      const int irCh = node.convolverChannels == 1
                           ? 0
                           : std::min(ch, node.convolverChannels - 1);
      const auto irBase = static_cast<size_t>(irCh * node.convolverFrames);
      double sum = 0.0;
      int read = node.convolverWrite;
      for (int k = 0; k < node.convolverFrames; ++k) {
        sum += history[static_cast<size_t>(read)] *
               node.convolverBuffer[irBase + static_cast<size_t>(k)];
        if (--read < 0) {
          read = node.convolverFrames - 1;
        }
      }
      node.current.channel(ch)[i] =
          std::isfinite(sum) ? static_cast<float>(sum) : 0.0f;
    }
    node.convolverWrite =
        (node.convolverWrite + 1) % std::max(1, node.convolverFrames);
  }
}

void Engine::renderAnalyser(Node &node, const AudioBus &input) {
  node.current = input;
  if (node.analyserTime.empty()) {
    node.analyserTime.assign(static_cast<size_t>(node.analyserFftSize), 0.0f);
  }
  for (int i = 0; i < renderFrames; ++i) {
    const float sample =
        input.channels > 0 && input.frames > i ? input.channel(0)[i] : 0.0f;
    node.analyserTime.erase(node.analyserTime.begin());
    node.analyserTime.push_back(sample);
  }
}

void Engine::renderMediaStreamSource(Node &node) {
  node.current.resize(renderChannels, renderFrames);
  node.current.clear();
  if (realtimeInput.frames <= 0 || realtimeInput.channels <= 0) {
    return;
  }
  const int frames = std::min(renderFrames, realtimeInput.frames);
  for (int ch = 0; ch < renderChannels; ++ch) {
    const int srcCh = realtimeInput.channels == 1
                          ? 0
                          : std::min(ch, realtimeInput.channels - 1);
    const float *src = realtimeInput.channel(srcCh);
    float *dst = node.current.channel(ch);
    if (src && dst) {
      std::copy(src, src + frames, dst);
      if (frames < renderFrames) {
        std::fill(dst + frames, dst + renderFrames, 0.0f);
      }
    }
  }
}

void Engine::renderWorklet(Node &node, const AudioBus &input) {
  node.current.resize(renderChannels, renderFrames);
  node.current.clear();
  if (!node.bridge || !node.bridge->active.load(std::memory_order_acquire)) {
    return;
  }
  if (node.workletLastOutput.size() <
      static_cast<size_t>(node.bridge->outputChannels)) {
    node.workletLastOutput.assign(
        static_cast<size_t>(node.bridge->outputChannels), 0.0f);
  }
  for (int ch = 0; ch < node.bridge->inputChannels; ++ch) {
    if (auto *rb = node.bridge->toIsolate->getChannel(ch)) {
      const float *src =
          ch < input.channels ? input.channel(ch) : node.current.channel(0);
      const int written = rb->write(src, renderFrames);
      if (written < renderFrames) {
        node.bridge->droppedInputSamples.fetch_add(renderFrames - written,
                                                   std::memory_order_relaxed);
      }
    }
  }
  std::vector<float> tmp(static_cast<size_t>(renderFrames), 0.0f);
  for (int ch = 0; ch < std::min(renderChannels, node.bridge->outputChannels);
       ++ch) {
    std::fill(tmp.begin(), tmp.end(), 0.0f);
    int read = 0;
    if (auto *rb = node.bridge->fromIsolate->getChannel(ch)) {
      read = rb->read(tmp.data(), renderFrames);
    }
    float held = node.workletLastOutput[static_cast<size_t>(ch)];
    if (read > 0) {
      held = tmp[static_cast<size_t>(read - 1)];
    }
    if (read < renderFrames) {
      std::fill(tmp.begin() + read, tmp.end(), held);
      node.bridge->outputUnderrunSamples.fetch_add(renderFrames - read,
                                                   std::memory_order_relaxed);
    }
    node.workletLastOutput[static_cast<size_t>(ch)] = held;
    std::copy(tmp.begin(), tmp.end(), node.current.channel(ch));
  }
}

void Engine::setRealtimeInputInterleaved(const float *input, int frames,
                                         int channels) {
  if (!input || frames <= 0 || channels <= 0) {
    realtimeInput.resize(1, 0);
    return;
  }
  const int storedChannels =
      channels == 1 && outputChannels.load(std::memory_order_relaxed) > 1 ? 2
                                                                          : channels;
  realtimeInput.resize(storedChannels, frames);
  for (int i = 0; i < frames; ++i) {
    for (int ch = 0; ch < channels; ++ch) {
      realtimeInput.channel(ch)[i] =
          input[static_cast<size_t>(i * channels + ch)];
    }
  }
  if (channels == 1 && storedChannels > 1) {
    float *left = realtimeInput.channel(0);
    float *right = realtimeInput.channel(1);
    if (left && right) {
      std::copy(left, left + frames, right);
    }
  }
}

void Engine::setRealtimeInputPlanar(const float *input, int frames,
                                    int channels) {
  if (!input || frames <= 0 || channels <= 0) {
    realtimeInput.resize(1, 0);
    return;
  }
  const int storedChannels =
      channels == 1 && outputChannels.load(std::memory_order_relaxed) > 1 ? 2
                                                                          : channels;
  realtimeInput.resize(storedChannels, frames);
  for (int ch = 0; ch < channels; ++ch) {
    const float *src = input + static_cast<size_t>(ch * frames);
    float *dst = realtimeInput.channel(ch);
    if (src && dst) {
      std::copy(src, src + frames, dst);
    }
  }
  if (channels == 1 && storedChannels > 1) {
    float *left = realtimeInput.channel(0);
    float *right = realtimeInput.channel(1);
    if (left && right) {
      std::copy(left, left + frames, right);
    }
  }
}

int32_t Engine::render(float *outData, int32_t frames, int32_t channels) {
  if (!outData || frames <= 0 || channels <= 0) {
    return 0;
  }
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  renderFrames = frames;
  renderChannels = channels;
  renderBlockStartTime = getCurrentTime();
  ++renderSerial;

  for (auto &[_, node] : nodes) {
    node.current.resize(renderChannels, renderFrames);
    node.current.clear();
  }

  std::vector<int32_t> stack;
  AudioBus &destination = renderNode(0, stack);
  for (int ch = 0; ch < channels; ++ch) {
    const float *src =
        ch < destination.channels ? destination.channel(ch) : nullptr;
    float *dst = outData + static_cast<size_t>(ch * frames);
    if (src) {
      std::copy(src, src + frames, dst);
    } else {
      std::fill(dst, dst + frames, 0.0f);
    }
  }
  copyCurrentToPrevious();
  const double sr = getSampleRate();
  if (sr > 0.0) {
    currentTime.store(renderBlockStartTime + frames / sr,
                      std::memory_order_release);
  }
  return frames;
}

static void fillFrequencyData(Engine::Node &node, float *magnitudes,
                              int32_t len, double sampleRate) {
  if (!magnitudes || len <= 0) {
    return;
  }
  const auto &time = node.analyserTime;
  const int n = static_cast<int>(time.size());
  if (n <= 0) {
    std::fill(magnitudes, magnitudes + len, -100.0f);
    return;
  }
  if (node.analyserPreviousDb.size() < static_cast<size_t>(len)) {
    node.analyserPreviousDb.assign(static_cast<size_t>(len),
                                   node.analyserMinDecibels);
  }
  for (int bin = 0; bin < len; ++bin) {
    double re = 0.0;
    double im = 0.0;
    for (int i = 0; i < n; ++i) {
      const double window = 0.5 - 0.5 * std::cos((2.0 * kPi * i) / (n - 1));
      const double phase = -2.0 * kPi * static_cast<double>(bin) * i / n;
      re += time[static_cast<size_t>(i)] * window * std::cos(phase);
      im += time[static_cast<size_t>(i)] * window * std::sin(phase);
    }
    const float mag =
        static_cast<float>(std::sqrt(re * re + im * im) / std::max(1, n));
    const float db = 20.0f * std::log10(std::max(mag, kSilentFloor));
    const float previous = node.analyserPreviousDb[static_cast<size_t>(bin)];
    const float smoothed =
        node.analyserSmoothing * previous + (1.0f - node.analyserSmoothing) * db;
    node.analyserPreviousDb[static_cast<size_t>(bin)] = smoothed;
    magnitudes[bin] = smoothed;
  }
  (void)sampleRate;
}

void Engine::analyserGetFloatFreqData(int32_t nodeId, float *data,
                                      int32_t len) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  auto *node = findNodeUnlocked(nodeId);
  if (!node || !data || len <= 0) {
    return;
  }
  fillFrequencyData(*node, data, len, getSampleRate());
}

void Engine::analyserGetByteFreqData(int32_t nodeId, uint8_t *data,
                                     int32_t len) {
  if (!data || len <= 0) {
    return;
  }
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  auto *node = findNodeUnlocked(nodeId);
  if (!node) {
    std::fill(data, data + len, 0);
    return;
  }
  std::vector<float> db(static_cast<size_t>(len), -100.0f);
  fillFrequencyData(*node, db.data(), len, getSampleRate());
  const float range =
      std::max(0.001f, node->analyserMaxDecibels - node->analyserMinDecibels);
  for (int i = 0; i < len; ++i) {
    const float normalized =
        (db[static_cast<size_t>(i)] - node->analyserMinDecibels) / range;
    data[i] = static_cast<uint8_t>(clampFloat(normalized, 0.0f, 1.0f) * 255.0f);
  }
}

void Engine::analyserGetFloatTimeData(int32_t nodeId, float *data,
                                      int32_t len) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  const auto *node = findNodeUnlocked(nodeId);
  if (!node || !data || len <= 0 || node->analyserTime.empty()) {
    if (data && len > 0) {
      std::fill(data, data + len, 0.0f);
    }
    return;
  }
  for (int i = 0; i < len; ++i) {
    const size_t idx =
        static_cast<size_t>(i) * node->analyserTime.size() / len;
    data[i] = node->analyserTime[std::min(idx, node->analyserTime.size() - 1)];
  }
}

void Engine::analyserGetByteTimeData(int32_t nodeId, uint8_t *data,
                                     int32_t len) {
  if (!data || len <= 0) {
    return;
  }
  std::vector<float> time(static_cast<size_t>(len), 0.0f);
  analyserGetFloatTimeData(nodeId, time.data(), len);
  for (int i = 0; i < len; ++i) {
    const float normalized = clampFloat(time[static_cast<size_t>(i)] * 0.5f +
                                            0.5f,
                                        0.0f, 1.0f);
    data[i] = static_cast<uint8_t>(normalized * 255.0f);
  }
}

void Engine::biquadGetFrequencyResponse(int32_t nodeId, const float *frequencyHz,
                                        float *magResponse,
                                        float *phaseResponse, int32_t len) {
  if (!frequencyHz || !magResponse || !phaseResponse || len <= 0) {
    return;
  }
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  auto *node = findNodeUnlocked(nodeId);
  if (!node) {
    std::fill(magResponse, magResponse + len, 0.0f);
    std::fill(phaseResponse, phaseResponse + len, 0.0f);
    return;
  }
  const float baseFreq = currentParam(*node, "frequency", 350.0f);
  const float detune = currentParam(*node, "detune", 0.0f);
  const float q = currentParam(*node, "Q", 1.0f);
  const float gain = currentParam(*node, "gain", 0.0f);
  const float effectiveFreq = baseFreq * std::pow(2.0f, detune / 1200.0f);
  const auto c = makeBiquad(node->filterType, effectiveFreq, q, gain,
                            getSampleRate());
  for (int i = 0; i < len; ++i) {
    const double omega = 2.0 * kPi * frequencyHz[i] / getSampleRate();
    const double c1 = std::cos(omega);
    const double s1 = -std::sin(omega);
    const double c2 = std::cos(2.0 * omega);
    const double s2 = -std::sin(2.0 * omega);
    const double numRe = c.b0 + c.b1 * c1 + c.b2 * c2;
    const double numIm = c.b1 * s1 + c.b2 * s2;
    const double denRe = 1.0 + c.a1 * c1 + c.a2 * c2;
    const double denIm = c.a1 * s1 + c.a2 * s2;
    const double denMag = std::max(kSilentFloor, static_cast<float>(denRe * denRe + denIm * denIm));
    const double hRe = (numRe * denRe + numIm * denIm) / denMag;
    const double hIm = (numIm * denRe - numRe * denIm) / denMag;
    magResponse[i] = static_cast<float>(std::sqrt(hRe * hRe + hIm * hIm));
    phaseResponse[i] = static_cast<float>(std::atan2(hIm, hRe));
  }
}

void Engine::iirGetFrequencyResponse(int32_t nodeId, const float *frequencyHz,
                                     float *magResponse, float *phaseResponse,
                                     int32_t len) {
  if (!frequencyHz || !magResponse || !phaseResponse || len <= 0) {
    return;
  }
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  auto *node = findNodeUnlocked(nodeId);
  if (!node || node->iirFeedforward.empty() || node->iirFeedback.empty()) {
    std::fill(magResponse, magResponse + len, 0.0f);
    std::fill(phaseResponse, phaseResponse + len, 0.0f);
    return;
  }

  const double sr = getSampleRate();
  for (int i = 0; i < len; ++i) {
    const double omega = 2.0 * kPi * frequencyHz[i] / sr;
    double numRe = 0.0;
    double numIm = 0.0;
    for (size_t k = 0; k < node->iirFeedforward.size(); ++k) {
      const double phase = -omega * static_cast<double>(k);
      numRe += node->iirFeedforward[k] * std::cos(phase);
      numIm += node->iirFeedforward[k] * std::sin(phase);
    }
    double denRe = 0.0;
    double denIm = 0.0;
    for (size_t k = 0; k < node->iirFeedback.size(); ++k) {
      const double phase = -omega * static_cast<double>(k);
      denRe += node->iirFeedback[k] * std::cos(phase);
      denIm += node->iirFeedback[k] * std::sin(phase);
    }
    const double denMag = denRe * denRe + denIm * denIm;
    if (denMag <= kSilentFloor) {
      magResponse[i] = 0.0f;
      phaseResponse[i] = 0.0f;
      continue;
    }
    const double hRe = (numRe * denRe + numIm * denIm) / denMag;
    const double hIm = (numIm * denRe - numRe * denIm) / denMag;
    magResponse[i] = static_cast<float>(std::sqrt(hRe * hRe + hIm * hIm));
    phaseResponse[i] = static_cast<float>(std::atan2(hIm, hRe));
  }
}

float Engine::compressorGetReduction(int32_t nodeId) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  const auto *node = findNodeUnlocked(nodeId);
  return node ? node->compressorReduction : 0.0f;
}

void Engine::pannerSetPanningModel(int32_t nodeId, int model) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  if (auto *node = findNodeUnlocked(nodeId)) {
    node->panningModel = std::max(0, std::min(1, model));
  }
}

void Engine::pannerSetDistanceModel(int32_t nodeId, int model) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  if (auto *node = findNodeUnlocked(nodeId)) {
    node->distanceModel = std::max(0, std::min(2, model));
  }
}

void Engine::pannerSetRefDistance(int32_t nodeId, double value) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  if (auto *node = findNodeUnlocked(nodeId)) {
    node->refDistance = std::max(0.0f, static_cast<float>(value));
  }
}

void Engine::pannerSetMaxDistance(int32_t nodeId, double value) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  if (auto *node = findNodeUnlocked(nodeId)) {
    node->maxDistance = std::max(node->refDistance, static_cast<float>(value));
  }
}

void Engine::pannerSetRolloffFactor(int32_t nodeId, double value) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  if (auto *node = findNodeUnlocked(nodeId)) {
    node->rolloffFactor = std::max(0.0f, static_cast<float>(value));
  }
}

void Engine::pannerSetConeInnerAngle(int32_t nodeId, double value) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  if (auto *node = findNodeUnlocked(nodeId)) {
    node->coneInnerAngle = clampFloat(static_cast<float>(value), 0.0f, 360.0f);
  }
}

void Engine::pannerSetConeOuterAngle(int32_t nodeId, double value) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  if (auto *node = findNodeUnlocked(nodeId)) {
    node->coneOuterAngle = clampFloat(static_cast<float>(value), 0.0f, 360.0f);
  }
}

void Engine::pannerSetConeOuterGain(int32_t nodeId, double value) {
  std::lock_guard<std::recursive_mutex> lock(graphMtx);
  if (auto *node = findNodeUnlocked(nodeId)) {
    node->coneOuterGain = clampFloat(static_cast<float>(value), 0.0f, 1.0f);
  }
}

void Engine::requestMediaInput() {
  mediaInputRequested.store(true, std::memory_order_release);
#if defined(WAJUCE_USE_APPLE_AUDIOUNIT) && WAJUCE_USE_APPLE_AUDIOUNIT
  if (state.load(std::memory_order_acquire) == 1) {
    closeAppleAudioUnit();
    ensureAppleAudioUnit();
  }
#endif
}

#if defined(WAJUCE_USE_RTAUDIO) && WAJUCE_USE_RTAUDIO
bool Engine::ensureRealtimeStream() {
  if (realtimeOpen) {
    if (realtime && !realtime->isStreamRunning()) {
      realtime->startStream();
    }
    return true;
  }
  try {
    realtime = std::make_unique<RtAudio>();
    if (realtime->getDeviceCount() == 0) {
      WA_LOG("RtAudio found no output devices");
      return false;
    }
    RtAudio::StreamParameters outParams;
    outParams.deviceId = realtime->getDefaultOutputDevice();
    const auto outInfo = realtime->getDeviceInfo(outParams.deviceId);
    outParams.nChannels = std::min<unsigned int>(
        static_cast<unsigned int>(
            std::max(1, outputChannels.load(std::memory_order_relaxed))),
        std::max(1u, outInfo.outputChannels));
    outParams.firstChannel = 0;
    outputChannels.store(static_cast<int>(outParams.nChannels),
                         std::memory_order_release);

    RtAudio::StreamParameters inParams;
    RtAudio::StreamParameters *inPtr = nullptr;
    if (inputChannels.load(std::memory_order_relaxed) > 0) {
      inParams.deviceId = realtime->getDefaultInputDevice();
      if (inParams.deviceId != 0) {
        const auto inInfo = realtime->getDeviceInfo(inParams.deviceId);
        if (inInfo.inputChannels > 0) {
          inParams.nChannels = std::min<unsigned int>(
              static_cast<unsigned int>(
                  std::max(1, inputChannels.load(std::memory_order_relaxed))),
              inInfo.inputChannels);
          inParams.firstChannel = 0;
          inputChannels.store(static_cast<int>(inParams.nChannels),
                              std::memory_order_release);
          inPtr = &inParams;
        } else {
          inputChannels.store(0, std::memory_order_release);
        }
      }
    }

    unsigned int frames =
        static_cast<unsigned int>(std::max(32, bufferSize.load()));
    RtAudio::StreamOptions options;
    options.flags = RTAUDIO_MINIMIZE_LATENCY;
    options.streamName = "wajuce";
    auto err = realtime->openStream(
        &outParams, inPtr, RTAUDIO_FLOAT32,
        static_cast<unsigned int>(std::max(1.0, getSampleRate())), &frames,
        &Engine::rtAudioCallback, this, &options);
    if (err != RTAUDIO_NO_ERROR && inPtr != nullptr) {
      WA_LOG("RtAudio duplex openStream failed: %d; retrying output-only",
             static_cast<int>(err));
      if (realtime->isStreamOpen()) {
        realtime->closeStream();
      }
      inPtr = nullptr;
      inputChannels.store(0, std::memory_order_release);
      frames = static_cast<unsigned int>(std::max(32, bufferSize.load()));
      err = realtime->openStream(
          &outParams, nullptr, RTAUDIO_FLOAT32,
          static_cast<unsigned int>(std::max(1.0, getSampleRate())), &frames,
          &Engine::rtAudioCallback, this, &options);
    }
    if (err != RTAUDIO_NO_ERROR) {
      WA_LOG("RtAudio openStream failed: %d", static_cast<int>(err));
      return false;
    }
    bufferSize.store(static_cast<int>(frames), std::memory_order_release);
    realtimeOpen = true;
    const auto startErr = realtime->startStream();
    if (startErr != RTAUDIO_NO_ERROR && startErr != RTAUDIO_WARNING) {
      WA_LOG("RtAudio startStream failed: %d", static_cast<int>(startErr));
      return false;
    }
    return true;
  } catch (const std::exception &e) {
    WA_LOG("RtAudio exception: %s", e.what());
    return false;
  }
}

void Engine::closeRealtimeStream() {
  if (!realtime) {
    realtimeOpen = false;
    return;
  }
  try {
    if (realtime->isStreamRunning()) {
      realtime->stopStream();
    }
    if (realtime->isStreamOpen()) {
      realtime->closeStream();
    }
  } catch (const std::exception &e) {
    WA_LOG("RtAudio close exception: %s", e.what());
  }
  realtimeOpen = false;
}

int Engine::rtAudioCallback(void *outputBuffer, void *inputBuffer, unsigned int nFrames,
                            double, RtAudioStreamStatus, void *userData) {
  auto *engine = static_cast<Engine *>(userData);
  auto *out = static_cast<float *>(outputBuffer);
  if (!engine || !out) {
    return 0;
  }
  const int channels =
      std::max(1, engine->outputChannels.load(std::memory_order_relaxed));
  if (inputBuffer) {
    const int inChannels =
        std::max(1, engine->inputChannels.load(std::memory_order_relaxed));
    engine->setRealtimeInputInterleaved(static_cast<const float *>(inputBuffer),
                                        static_cast<int>(nFrames), inChannels);
  }
  std::vector<float> planar(static_cast<size_t>(channels * nFrames), 0.0f);
  engine->render(planar.data(), static_cast<int32_t>(nFrames), channels);
  for (unsigned int i = 0; i < nFrames; ++i) {
    for (int ch = 0; ch < channels; ++ch) {
      out[i * channels + ch] =
          planar[static_cast<size_t>(ch * nFrames + i)];
    }
  }
  return 0;
}
#endif

#if defined(WAJUCE_USE_APPLE_AUDIOUNIT) && WAJUCE_USE_APPLE_AUDIOUNIT
bool Engine::ensureAppleAudioUnit() {
  if (appleAudioUnitOpen && appleAudioUnit) {
    AudioOutputUnitStart(appleAudioUnit);
    return true;
  }

  bool inputAllowed = mediaInputRequested.load(std::memory_order_acquire) &&
                      inputChannels.load(std::memory_order_relaxed) > 0;

#if defined(__OBJC__)
  @autoreleasepool {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error = nil;
    const AVAudioSessionCategoryOptions options =
        AVAudioSessionCategoryOptionDefaultToSpeaker |
        AVAudioSessionCategoryOptionAllowBluetooth |
        AVAudioSessionCategoryOptionMixWithOthers;
    if (![session setCategory:AVAudioSessionCategoryPlayAndRecord
                  withOptions:options
                        error:&error]) {
      WA_LOG("AVAudioSession setCategory failed: %s",
             error.localizedDescription.UTF8String ?: "unknown");
    }
    if (inputAllowed) {
      if (session.recordPermission ==
          AVAudioSessionRecordPermissionUndetermined) {
        inputAllowed = false;
        if (!appleInputPermissionPending.exchange(
                true, std::memory_order_acq_rel)) {
          std::weak_ptr<Engine> weakSelf;
          try {
            weakSelf = shared_from_this();
          } catch (const std::bad_weak_ptr &) {
          }
          [session requestRecordPermission:^(BOOL granted) {
            WA_LOG("AVAudioSession record permission: %s",
                   granted ? "granted" : "denied");
            if (auto engine = weakSelf.lock()) {
              engine->appleInputPermissionPending.store(
                  false, std::memory_order_release);
              if (granted && engine->state.load(std::memory_order_acquire) == 1) {
                dispatch_async(dispatch_get_main_queue(), ^{
                  if (auto activeEngine = weakSelf.lock()) {
                    activeEngine->closeAppleAudioUnit();
                    activeEngine->ensureAppleAudioUnit();
                  }
                });
              }
            }
          }];
        }
      } else if (session.recordPermission ==
                 AVAudioSessionRecordPermissionDenied) {
        inputAllowed = false;
        WA_LOG("AVAudioSession record permission denied");
      }
    }
    error = nil;
    const double requestedSampleRate = getSampleRate();
    if (requestedSampleRate > 0.0 &&
        ![session setPreferredSampleRate:requestedSampleRate error:&error]) {
      WA_LOG("AVAudioSession setPreferredSampleRate failed: %s",
             error.localizedDescription.UTF8String ?: "unknown");
    }
    if (inputAllowed) {
      error = nil;
      if (![session setPreferredInputNumberOfChannels:1 error:&error]) {
        WA_LOG("AVAudioSession setPreferredInputNumberOfChannels failed: %s",
               error.localizedDescription.UTF8String ?: "unknown");
      }
    }
    error = nil;
    const double requestedBufferDuration =
        static_cast<double>(std::max(32, bufferSize.load())) /
        std::max(1.0, requestedSampleRate);
    if (![session setPreferredIOBufferDuration:requestedBufferDuration
                                         error:&error]) {
      WA_LOG("AVAudioSession setPreferredIOBufferDuration failed: %s",
             error.localizedDescription.UTF8String ?: "unknown");
    }
    error = nil;
    if (![session setActive:YES error:&error]) {
      WA_LOG("AVAudioSession setActive failed: %s",
             error.localizedDescription.UTF8String ?: "unknown");
    }
    if (session.sampleRate > 0.0) {
      sampleRate.store(session.sampleRate, std::memory_order_release);
    }
    if (inputAllowed && session.inputNumberOfChannels > 0) {
      inputChannels.store(static_cast<int>(session.inputNumberOfChannels),
                          std::memory_order_release);
    } else if (inputAllowed) {
      inputChannels.store(1, std::memory_order_release);
    }
    if (session.IOBufferDuration > 0.0 && session.sampleRate > 0.0) {
      const int actualFrames = static_cast<int>(
          std::lround(session.IOBufferDuration * session.sampleRate));
      if (actualFrames > 0) {
        bufferSize.store(actualFrames, std::memory_order_release);
      }
    }
  }
#endif

  AudioComponentDescription desc{};
  desc.componentType = kAudioUnitType_Output;
  desc.componentSubType = kAudioUnitSubType_RemoteIO;
  desc.componentManufacturer = kAudioUnitManufacturer_Apple;

  AudioComponent component = AudioComponentFindNext(nullptr, &desc);
  if (!component) {
    WA_LOG("RemoteIO AudioUnit not found");
    return false;
  }

  OSStatus status = AudioComponentInstanceNew(component, &appleAudioUnit);
  if (status != noErr || !appleAudioUnit) {
    WA_LOG("AudioComponentInstanceNew failed: %d", static_cast<int>(status));
    appleAudioUnit = nullptr;
    return false;
  }

  UInt32 enabled = 1;
  status = AudioUnitSetProperty(appleAudioUnit, kAudioOutputUnitProperty_EnableIO,
                                kAudioUnitScope_Output, 0, &enabled,
                                sizeof(enabled));
  if (status != noErr) {
    WA_LOG("RemoteIO output enable failed: %d", static_cast<int>(status));
    closeAppleAudioUnit();
    return false;
  }

  const int inputChannelCount =
      inputAllowed ? std::max(1, inputChannels.load(std::memory_order_relaxed))
                   : 0;
  if (inputChannelCount > 0) {
    UInt32 inputEnabled = 1;
    status = AudioUnitSetProperty(appleAudioUnit,
                                  kAudioOutputUnitProperty_EnableIO,
                                  kAudioUnitScope_Input, 1, &inputEnabled,
                                  sizeof(inputEnabled));
    if (status != noErr) {
      WA_LOG("RemoteIO input enable failed: %d", static_cast<int>(status));
      inputChannels.store(0, std::memory_order_release);
    }
  }

  const int channels =
      std::max(1, outputChannels.load(std::memory_order_relaxed));
  AudioStreamBasicDescription format{};
  format.mSampleRate = std::max(1.0, getSampleRate());
  format.mFormatID = kAudioFormatLinearPCM;
  format.mFormatFlags =
      kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved;
  format.mBytesPerPacket = sizeof(float);
  format.mFramesPerPacket = 1;
  format.mBytesPerFrame = sizeof(float);
  format.mChannelsPerFrame = static_cast<UInt32>(channels);
  format.mBitsPerChannel = 8 * sizeof(float);

  status = AudioUnitSetProperty(appleAudioUnit, kAudioUnitProperty_StreamFormat,
                                kAudioUnitScope_Input, 0, &format,
                                sizeof(format));
  if (status != noErr) {
    WA_LOG("RemoteIO stream format failed: %d", static_cast<int>(status));
    closeAppleAudioUnit();
    return false;
  }

  if (inputChannels.load(std::memory_order_relaxed) > 0) {
    AudioStreamBasicDescription inputFormat = format;
    inputFormat.mChannelsPerFrame = static_cast<UInt32>(
        std::max(1, inputChannels.load(std::memory_order_relaxed)));
    status = AudioUnitSetProperty(appleAudioUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Output, 1, &inputFormat,
                                  sizeof(inputFormat));
    if (status != noErr) {
      WA_LOG("RemoteIO input stream format failed: %d",
             static_cast<int>(status));
      inputChannels.store(0, std::memory_order_release);
    }
  }

  UInt32 maxFrames = static_cast<UInt32>(std::max(32, bufferSize.load()));
  AudioUnitSetProperty(appleAudioUnit, kAudioUnitProperty_MaximumFramesPerSlice,
                       kAudioUnitScope_Global, 0, &maxFrames,
                       sizeof(maxFrames));

  AURenderCallbackStruct callback{};
  callback.inputProc = &Engine::appleAudioUnitCallback;
  callback.inputProcRefCon = this;
  status = AudioUnitSetProperty(appleAudioUnit,
                                kAudioUnitProperty_SetRenderCallback,
                                kAudioUnitScope_Input, 0, &callback,
                                sizeof(callback));
  if (status != noErr) {
    WA_LOG("RemoteIO callback install failed: %d", static_cast<int>(status));
    closeAppleAudioUnit();
    return false;
  }

  status = AudioUnitInitialize(appleAudioUnit);
  if (status != noErr) {
    WA_LOG("RemoteIO initialize failed: %d", static_cast<int>(status));
    closeAppleAudioUnit();
    return false;
  }

  appleAudioUnitOpen = true;
  status = AudioOutputUnitStart(appleAudioUnit);
  if (status != noErr) {
    WA_LOG("RemoteIO start failed: %d", static_cast<int>(status));
    closeAppleAudioUnit();
    return false;
  }
  return true;
}

void Engine::closeAppleAudioUnit() {
  if (!appleAudioUnit) {
    appleAudioUnitOpen = false;
    return;
  }
  AudioOutputUnitStop(appleAudioUnit);
  if (appleAudioUnitOpen) {
    AudioUnitUninitialize(appleAudioUnit);
  }
  AudioComponentInstanceDispose(appleAudioUnit);
  appleAudioUnit = nullptr;
  appleAudioUnitOpen = false;
}

OSStatus Engine::appleAudioUnitCallback(void *inRefCon,
                                        AudioUnitRenderActionFlags *flags,
                                        const AudioTimeStamp *timeStamp, UInt32,
                                        UInt32 frameCount,
                                        AudioBufferList *ioData) {
  auto *engine = static_cast<Engine *>(inRefCon);
  if (!engine || !ioData || frameCount == 0) {
    return noErr;
  }

  const int inputChannelCount =
      std::max(0, engine->inputChannels.load(std::memory_order_relaxed));
  if (engine->appleAudioUnit && inputChannelCount > 0 && timeStamp) {
    const size_t bufferListSize =
        sizeof(AudioBufferList) +
        static_cast<size_t>(inputChannelCount - 1) * sizeof(AudioBuffer);
    std::vector<uint8_t> inputListStorage(bufferListSize, 0);
    auto *inputList =
        reinterpret_cast<AudioBufferList *>(inputListStorage.data());
    std::vector<float> inputPlanar(
        static_cast<size_t>(inputChannelCount) *
            static_cast<size_t>(frameCount),
        0.0f);
    inputList->mNumberBuffers = static_cast<UInt32>(inputChannelCount);
    for (int ch = 0; ch < inputChannelCount; ++ch) {
      inputList->mBuffers[ch].mNumberChannels = 1;
      inputList->mBuffers[ch].mDataByteSize = frameCount * sizeof(float);
      inputList->mBuffers[ch].mData =
          inputPlanar.data() + static_cast<size_t>(ch) * frameCount;
    }
    AudioUnitRenderActionFlags inputFlags = flags ? *flags : 0;
    const OSStatus inputStatus =
        AudioUnitRender(engine->appleAudioUnit, &inputFlags, timeStamp, 1,
                        frameCount, inputList);
    if (inputStatus == noErr) {
      engine->setRealtimeInputPlanar(inputPlanar.data(),
                                     static_cast<int>(frameCount),
                                     inputChannelCount);
    }
  }

  const int channels =
      std::max(1, engine->outputChannels.load(std::memory_order_relaxed));
  std::vector<float> planar(
      static_cast<size_t>(channels) * static_cast<size_t>(frameCount), 0.0f);
  if (engine->state.load(std::memory_order_relaxed) == 1) {
    engine->render(planar.data(), static_cast<int32_t>(frameCount), channels);
  }

  if (ioData->mNumberBuffers == 1 &&
      ioData->mBuffers[0].mNumberChannels > 1) {
    auto *out = static_cast<float *>(ioData->mBuffers[0].mData);
    if (!out) {
      return noErr;
    }
    const UInt32 outChannels = ioData->mBuffers[0].mNumberChannels;
    const size_t samples =
        static_cast<size_t>(frameCount) * static_cast<size_t>(outChannels);
    std::fill(out, out + samples, 0.0f);
    for (UInt32 i = 0; i < frameCount; ++i) {
      for (UInt32 ch = 0; ch < outChannels; ++ch) {
        const int srcCh = static_cast<int>(std::min<UInt32>(
            ch, static_cast<UInt32>(std::max(0, channels - 1))));
        out[static_cast<size_t>(i) * outChannels + ch] =
            planar[static_cast<size_t>(srcCh) * frameCount + i];
      }
    }
    return noErr;
  }

  for (UInt32 bufferIndex = 0; bufferIndex < ioData->mNumberBuffers;
       ++bufferIndex) {
    AudioBuffer &buffer = ioData->mBuffers[bufferIndex];
    auto *out = static_cast<float *>(buffer.mData);
    if (!out) {
      continue;
    }
    const UInt32 bufferChannels = std::max<UInt32>(1, buffer.mNumberChannels);
    const size_t samples =
        static_cast<size_t>(frameCount) * static_cast<size_t>(bufferChannels);
    std::fill(out, out + samples, 0.0f);
    for (UInt32 localCh = 0; localCh < bufferChannels; ++localCh) {
      const int srcCh = static_cast<int>(std::min<UInt32>(
          bufferIndex + localCh, static_cast<UInt32>(std::max(0, channels - 1))));
      for (UInt32 i = 0; i < frameCount; ++i) {
        out[static_cast<size_t>(i) * bufferChannels + localCh] =
            planar[static_cast<size_t>(srcCh) * frameCount + i];
      }
    }
  }
  return noErr;
}
#endif

} // namespace wajuce

using namespace wajuce;

extern "C" {

FFI_PLUGIN_EXPORT int32_t wajuce_context_create(int32_t sr, int32_t bs,
                                                int32_t inCh, int32_t outCh) {
  auto engine =
      std::make_shared<wajuce::Engine>((double)sr, bs, inCh, outCh);
  std::lock_guard<std::mutex> lock(wajuce::g_engineMtx);
  const int32_t id = wajuce::g_nextCtxId++;
  wajuce::g_engines[id] = std::move(engine);
  return id;
}

FFI_PLUGIN_EXPORT void wajuce_context_destroy(int32_t id) {
  std::lock_guard<std::mutex> lock(wajuce::g_engineMtx);
  wajuce::g_engines.erase(id);
}

FFI_PLUGIN_EXPORT double wajuce_context_get_time(int32_t id) {
  auto e = wajuce::getEngine(id);
  return e ? e->getCurrentTime() : 0.0;
}

FFI_PLUGIN_EXPORT int32_t wajuce_context_get_live_node_count(int32_t id) {
  auto e = wajuce::getEngine(id);
  return e ? e->getLiveNodeCount() : 0;
}

FFI_PLUGIN_EXPORT int32_t wajuce_context_get_feedback_bridge_count(int32_t id) {
  auto e = wajuce::getEngine(id);
  return e ? e->getFeedbackBridgeCount() : 0;
}

FFI_PLUGIN_EXPORT int32_t
wajuce_context_get_machine_voice_group_count(int32_t id) {
  auto e = wajuce::getEngine(id);
  return e ? e->getMachineVoiceGroupCount() : 0;
}

FFI_PLUGIN_EXPORT double wajuce_context_get_sample_rate(int32_t id) {
  auto e = wajuce::getEngine(id);
  return e ? e->getSampleRate() : 44100.0;
}

FFI_PLUGIN_EXPORT int32_t wajuce_context_get_bit_depth(int32_t id) {
  auto e = wajuce::getEngine(id);
  return e ? e->getCurrentBitDepth() : 32;
}

FFI_PLUGIN_EXPORT int32_t
wajuce_context_set_preferred_sample_rate(int32_t id, double preferredSr) {
  auto e = wajuce::getEngine(id);
  return e && e->setPreferredSampleRate(preferredSr) ? 1 : 0;
}

FFI_PLUGIN_EXPORT int32_t
wajuce_context_set_preferred_bit_depth(int32_t id, int32_t bitDepth) {
  auto e = wajuce::getEngine(id);
  return e && e->setPreferredBitDepth(bitDepth) ? 1 : 0;
}

FFI_PLUGIN_EXPORT int32_t wajuce_context_get_state(int32_t id) {
  auto e = wajuce::getEngine(id);
  return e ? e->getState() : 2;
}

FFI_PLUGIN_EXPORT void wajuce_context_resume(int32_t id) {
  if (auto e = wajuce::getEngine(id)) {
    e->resume();
  }
}

FFI_PLUGIN_EXPORT void wajuce_context_suspend(int32_t id) {
  if (auto e = wajuce::getEngine(id)) {
    e->suspend();
  }
}

FFI_PLUGIN_EXPORT void wajuce_context_close(int32_t id) {
  if (auto e = wajuce::getEngine(id)) {
    e->close();
  }
}

FFI_PLUGIN_EXPORT int32_t wajuce_context_get_destination_id(int32_t id) {
  auto e = wajuce::getEngine(id);
  return e ? e->getDestinationId() : 0;
}

FFI_PLUGIN_EXPORT int32_t wajuce_context_get_listener_id(int32_t id) {
  auto e = wajuce::getEngine(id);
  return e ? e->getListenerId() : -1;
}

FFI_PLUGIN_EXPORT int32_t wajuce_create_gain(int32_t id) {
  auto e = wajuce::getEngine(id);
  return e ? e->createGain() : -1;
}

FFI_PLUGIN_EXPORT int32_t wajuce_create_oscillator(int32_t id) {
  auto e = wajuce::getEngine(id);
  return e ? e->createOscillator() : -1;
}

FFI_PLUGIN_EXPORT int32_t wajuce_create_biquad_filter(int32_t id) {
  auto e = wajuce::getEngine(id);
  return e ? e->createBiquadFilter() : -1;
}

FFI_PLUGIN_EXPORT int32_t wajuce_create_compressor(int32_t id) {
  auto e = wajuce::getEngine(id);
  return e ? e->createCompressor() : -1;
}

FFI_PLUGIN_EXPORT int32_t wajuce_create_delay(int32_t id, float maxDelay) {
  auto e = wajuce::getEngine(id);
  return e ? e->createDelay(maxDelay) : -1;
}

FFI_PLUGIN_EXPORT int32_t wajuce_create_buffer_source(int32_t id) {
  auto e = wajuce::getEngine(id);
  return e ? e->createBufferSource() : -1;
}

FFI_PLUGIN_EXPORT int32_t wajuce_create_analyser(int32_t id) {
  auto e = wajuce::getEngine(id);
  return e ? e->createAnalyser() : -1;
}

FFI_PLUGIN_EXPORT int32_t wajuce_create_stereo_panner(int32_t id) {
  auto e = wajuce::getEngine(id);
  return e ? e->createStereoPanner() : -1;
}

FFI_PLUGIN_EXPORT int32_t wajuce_create_panner(int32_t id) {
  auto e = wajuce::getEngine(id);
  return e ? e->createPanner() : -1;
}

FFI_PLUGIN_EXPORT int32_t wajuce_create_wave_shaper(int32_t id) {
  auto e = wajuce::getEngine(id);
  return e ? e->createWaveShaper() : -1;
}

FFI_PLUGIN_EXPORT int32_t wajuce_create_constant_source(int32_t id) {
  auto e = wajuce::getEngine(id);
  return e ? e->createConstantSource() : -1;
}

FFI_PLUGIN_EXPORT int32_t wajuce_create_convolver(int32_t id) {
  auto e = wajuce::getEngine(id);
  return e ? e->createConvolver() : -1;
}

FFI_PLUGIN_EXPORT int32_t
wajuce_create_iir_filter(int32_t id, const double *feedforward,
                         int32_t feedforwardLen, const double *feedback,
                         int32_t feedbackLen) {
  auto e = wajuce::getEngine(id);
  return e ? e->createIIRFilter(feedforward, feedforwardLen, feedback,
                                feedbackLen)
           : -1;
}

FFI_PLUGIN_EXPORT int32_t wajuce_create_media_stream_source(int32_t id) {
  auto e = wajuce::getEngine(id);
  return e ? e->createMediaStreamSource() : -1;
}

FFI_PLUGIN_EXPORT int32_t wajuce_create_media_stream_destination(int32_t id) {
  auto e = wajuce::getEngine(id);
  return e ? e->createMediaStreamDestination() : -1;
}

FFI_PLUGIN_EXPORT int32_t wajuce_create_channel_splitter(int32_t id,
                                                         int32_t outputs) {
  auto e = wajuce::getEngine(id);
  return e ? e->createChannelSplitter(outputs) : -1;
}

FFI_PLUGIN_EXPORT int32_t wajuce_create_channel_merger(int32_t id,
                                                       int32_t inputs) {
  auto e = wajuce::getEngine(id);
  return e ? e->createChannelMerger(inputs) : -1;
}

FFI_PLUGIN_EXPORT int32_t wajuce_create_worklet_bridge(int32_t id,
                                                       int32_t inputs,
                                                       int32_t outputs) {
  auto e = wajuce::getEngine(id);
  return e ? e->createWorkletBridge(inputs, outputs) : -1;
}

FFI_PLUGIN_EXPORT void wajuce_create_machine_voice(int32_t id,
                                                   int32_t *resultIds) {
  if (auto e = wajuce::getEngine(id)) {
    e->createMachineVoice(resultIds);
  }
}

FFI_PLUGIN_EXPORT void wajuce_machine_voice_set_active(int32_t id,
                                                       int32_t nodeId,
                                                       int32_t active) {
  if (auto e = wajuce::getEngine(id)) {
    e->setMachineVoiceActive(nodeId, active != 0);
  }
}

FFI_PLUGIN_EXPORT void wajuce_context_remove_node(int32_t id, int32_t nodeId) {
  if (auto e = wajuce::getEngine(id)) {
    e->removeNode(nodeId);
  }
}

FFI_PLUGIN_EXPORT void wajuce_connect(int32_t id, int32_t src, int32_t dst,
                                      int32_t output, int32_t input) {
  if (auto e = wajuce::getEngine(id)) {
    e->connect(src, dst, output, input);
  }
}

FFI_PLUGIN_EXPORT void wajuce_connect_param(int32_t id, int32_t src,
                                            int32_t dst, const char *param,
                                            int32_t output) {
  if (auto e = wajuce::getEngine(id)) {
    e->connectParam(src, dst, param, output);
  }
}

FFI_PLUGIN_EXPORT void wajuce_disconnect(int32_t id, int32_t src,
                                         int32_t dst) {
  if (auto e = wajuce::getEngine(id)) {
    e->disconnect(src, dst);
  }
}

FFI_PLUGIN_EXPORT void wajuce_disconnect_output(int32_t id, int32_t src,
                                                int32_t output) {
  if (auto e = wajuce::getEngine(id)) {
    e->disconnectOutput(src, output);
  }
}

FFI_PLUGIN_EXPORT void wajuce_disconnect_node_output(int32_t id, int32_t src,
                                                     int32_t dst,
                                                     int32_t output) {
  if (auto e = wajuce::getEngine(id)) {
    e->disconnectNodeOutput(src, dst, output);
  }
}

FFI_PLUGIN_EXPORT void wajuce_disconnect_node_input(int32_t id, int32_t src,
                                                    int32_t dst,
                                                    int32_t output,
                                                    int32_t input) {
  if (auto e = wajuce::getEngine(id)) {
    e->disconnectNodeInput(src, dst, output, input);
  }
}

FFI_PLUGIN_EXPORT void wajuce_disconnect_param(int32_t id, int32_t src,
                                               int32_t dst, const char *param,
                                               int32_t output) {
  if (auto e = wajuce::getEngine(id)) {
    e->disconnectParam(src, dst, param, output);
  }
}

FFI_PLUGIN_EXPORT void wajuce_disconnect_all(int32_t id, int32_t src) {
  if (auto e = wajuce::getEngine(id)) {
    e->disconnectAll(src);
  }
}

FFI_PLUGIN_EXPORT void wajuce_param_set(int32_t nodeId, const char *param,
                                        float value) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->paramSet(nodeId, param, value);
  }
}

FFI_PLUGIN_EXPORT void wajuce_param_set_at_time(int32_t nodeId,
                                                const char *param, float value,
                                                double time) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->paramSetAtTime(nodeId, param, value, time);
  }
}

FFI_PLUGIN_EXPORT void wajuce_param_linear_ramp(int32_t nodeId,
                                                const char *param, float value,
                                                double endTime) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->paramLinearRamp(nodeId, param, value, endTime);
  }
}

FFI_PLUGIN_EXPORT void wajuce_param_exp_ramp(int32_t nodeId, const char *param,
                                             float value, double endTime) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->paramExpRamp(nodeId, param, value, endTime);
  }
}

FFI_PLUGIN_EXPORT void wajuce_param_set_target(int32_t nodeId,
                                               const char *param, float target,
                                               double startTime, float tc) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->paramSetTarget(nodeId, param, target, startTime, tc);
  }
}

FFI_PLUGIN_EXPORT void wajuce_param_set_value_curve(
    int32_t nodeId, const char *param, const float *values, int32_t length,
    double startTime, double duration) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->paramSetValueCurve(nodeId, param, values, length, startTime, duration);
  }
}

FFI_PLUGIN_EXPORT void wajuce_param_cancel(int32_t nodeId, const char *param,
                                           double cancelTime) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->paramCancel(nodeId, param, cancelTime);
  }
}

FFI_PLUGIN_EXPORT void wajuce_param_cancel_and_hold(int32_t nodeId,
                                                    const char *param,
                                                    double time) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->paramCancelAndHold(nodeId, param, time);
  }
}

FFI_PLUGIN_EXPORT float wajuce_param_get(int32_t nodeId, const char *param) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    return e->paramGet(nodeId, param);
  }
  return 0.0f;
}

FFI_PLUGIN_EXPORT void wajuce_osc_set_type(int32_t nodeId, int32_t type) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->oscSetType(nodeId, type);
  }
}

FFI_PLUGIN_EXPORT void wajuce_osc_start(int32_t nodeId, double when) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->oscStart(nodeId, when);
  }
}

FFI_PLUGIN_EXPORT void wajuce_osc_stop(int32_t nodeId, double when) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->oscStop(nodeId, when);
  }
}

FFI_PLUGIN_EXPORT void wajuce_osc_set_periodic_wave(int32_t nodeId,
                                                    const float *real,
                                                    const float *imag,
                                                    int32_t len,
                                                    int32_t disableNormalization) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->oscSetPeriodicWave(nodeId, real, imag, len, disableNormalization != 0);
  }
}

FFI_PLUGIN_EXPORT void wajuce_filter_set_type(int32_t nodeId, int32_t type) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->filterSetType(nodeId, type);
  }
}

FFI_PLUGIN_EXPORT void
wajuce_buffer_source_set_buffer(int32_t nodeId, const float *data,
                                int32_t frames, int32_t channels, int32_t sr) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->bufferSourceSetBuffer(nodeId, data, frames, channels, sr);
  }
}

FFI_PLUGIN_EXPORT void wajuce_buffer_source_start(int32_t nodeId,
                                                  double when) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->bufferSourceStart(nodeId, when);
  }
}

FFI_PLUGIN_EXPORT void
wajuce_buffer_source_start_with_offset(int32_t nodeId, double when,
                                       double offset, double duration,
                                       int32_t hasDuration) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->bufferSourceStart(nodeId, when, offset, duration, hasDuration != 0);
  }
}

FFI_PLUGIN_EXPORT void wajuce_buffer_source_stop(int32_t nodeId, double when) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->bufferSourceStop(nodeId, when);
  }
}

FFI_PLUGIN_EXPORT void wajuce_buffer_source_set_loop(int32_t nodeId,
                                                     int32_t loop) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->bufferSourceSetLoop(nodeId, loop != 0);
  }
}

FFI_PLUGIN_EXPORT void
wajuce_buffer_source_set_loop_points(int32_t nodeId, double loopStart,
                                     double loopEnd) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->bufferSourceSetLoopPoints(nodeId, loopStart, loopEnd);
  }
}

FFI_PLUGIN_EXPORT void wajuce_analyser_set_fft_size(int32_t nodeId,
                                                    int32_t size) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->analyserSetFftSize(nodeId, size);
  }
}

FFI_PLUGIN_EXPORT void wajuce_analyser_set_min_decibels(int32_t nodeId,
                                                        double value) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->analyserSetMinDecibels(nodeId, value);
  }
}

FFI_PLUGIN_EXPORT void wajuce_analyser_set_max_decibels(int32_t nodeId,
                                                        double value) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->analyserSetMaxDecibels(nodeId, value);
  }
}

FFI_PLUGIN_EXPORT void
wajuce_analyser_set_smoothing_time_constant(int32_t nodeId, double value) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->analyserSetSmoothingTimeConstant(nodeId, value);
  }
}

FFI_PLUGIN_EXPORT void
wajuce_analyser_get_byte_freq(int32_t nodeId, uint8_t *data, int32_t len) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->analyserGetByteFreqData(nodeId, data, len);
  }
}

FFI_PLUGIN_EXPORT void
wajuce_analyser_get_byte_time(int32_t nodeId, uint8_t *data, int32_t len) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->analyserGetByteTimeData(nodeId, data, len);
  }
}

FFI_PLUGIN_EXPORT void wajuce_analyser_get_float_freq(int32_t nodeId,
                                                      float *data,
                                                      int32_t len) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->analyserGetFloatFreqData(nodeId, data, len);
  }
}

FFI_PLUGIN_EXPORT void wajuce_analyser_get_float_time(int32_t nodeId,
                                                      float *data,
                                                      int32_t len) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->analyserGetFloatTimeData(nodeId, data, len);
  }
}

FFI_PLUGIN_EXPORT void wajuce_biquad_get_frequency_response(
    int32_t nodeId, const float *frequencyHz, float *magResponse,
    float *phaseResponse, int32_t len) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->biquadGetFrequencyResponse(nodeId, frequencyHz, magResponse,
                                  phaseResponse, len);
  }
}

FFI_PLUGIN_EXPORT void wajuce_iir_get_frequency_response(
    int32_t nodeId, const float *frequencyHz, float *magResponse,
    float *phaseResponse, int32_t len) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->iirGetFrequencyResponse(nodeId, frequencyHz, magResponse, phaseResponse,
                               len);
  }
}

FFI_PLUGIN_EXPORT float wajuce_compressor_get_reduction(int32_t nodeId) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    return e->compressorGetReduction(nodeId);
  }
  return 0.0f;
}

FFI_PLUGIN_EXPORT void wajuce_panner_set_panning_model(int32_t nodeId,
                                                       int32_t model) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->pannerSetPanningModel(nodeId, model);
  }
}

FFI_PLUGIN_EXPORT void wajuce_panner_set_distance_model(int32_t nodeId,
                                                        int32_t model) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->pannerSetDistanceModel(nodeId, model);
  }
}

FFI_PLUGIN_EXPORT void wajuce_panner_set_ref_distance(int32_t nodeId,
                                                      double value) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->pannerSetRefDistance(nodeId, value);
  }
}

FFI_PLUGIN_EXPORT void wajuce_panner_set_max_distance(int32_t nodeId,
                                                      double value) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->pannerSetMaxDistance(nodeId, value);
  }
}

FFI_PLUGIN_EXPORT void wajuce_panner_set_rolloff_factor(int32_t nodeId,
                                                        double value) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->pannerSetRolloffFactor(nodeId, value);
  }
}

FFI_PLUGIN_EXPORT void wajuce_panner_set_cone_inner_angle(int32_t nodeId,
                                                          double value) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->pannerSetConeInnerAngle(nodeId, value);
  }
}

FFI_PLUGIN_EXPORT void wajuce_panner_set_cone_outer_angle(int32_t nodeId,
                                                          double value) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->pannerSetConeOuterAngle(nodeId, value);
  }
}

FFI_PLUGIN_EXPORT void wajuce_panner_set_cone_outer_gain(int32_t nodeId,
                                                         double value) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->pannerSetConeOuterGain(nodeId, value);
  }
}

FFI_PLUGIN_EXPORT void
wajuce_wave_shaper_set_curve(int32_t nodeId, const float *data, int32_t len) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->waveShaperSetCurve(nodeId, data, len);
  }
}

FFI_PLUGIN_EXPORT void wajuce_wave_shaper_set_oversample(int32_t nodeId,
                                                         int32_t type) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->waveShaperSetOversample(nodeId, type);
  }
}

FFI_PLUGIN_EXPORT void
wajuce_convolver_set_buffer(int32_t nodeId, const float *data, int32_t frames,
                            int32_t channels, int32_t sr,
                            int32_t normalize) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->convolverSetBuffer(nodeId, data, frames, channels, sr, normalize != 0);
  }
}

FFI_PLUGIN_EXPORT void wajuce_convolver_set_normalize(int32_t nodeId,
                                                      int32_t normalize) {
  if (auto e = wajuce::findEngineForNode(nodeId)) {
    e->convolverSetNormalize(nodeId, normalize != 0);
  }
}

static std::shared_ptr<WorkletBridgeState>
getBridgeState(int32_t ctxId, int32_t bridgeId) {
  auto e = wajuce::getEngine(ctxId);
  if (!e) {
    return nullptr;
  }
  auto state = e->getWorkletBridgeState(bridgeId);
  if (!state || !state->active.load(std::memory_order_acquire)) {
    return nullptr;
  }
  return state;
}

FFI_PLUGIN_EXPORT float *wajuce_worklet_get_buffer_ptr(int32_t ctxId,
                                                       int32_t bridgeId,
                                                       int32_t direction,
                                                       int32_t channel) {
  auto state = getBridgeState(ctxId, bridgeId);
  if (!state) {
    return nullptr;
  }
  auto buffers = direction == 0 ? state->toIsolate : state->fromIsolate;
  auto *rb = buffers ? buffers->getChannel(channel) : nullptr;
  return rb ? rb->getBufferRawPtr() : nullptr;
}

FFI_PLUGIN_EXPORT int32_t
wajuce_worklet_get_input_channel_count(int32_t ctxId, int32_t bridgeId) {
  auto e = wajuce::getEngine(ctxId);
  return e ? e->getWorkletBridgeInputChannelCount(bridgeId) : 0;
}

FFI_PLUGIN_EXPORT int32_t
wajuce_worklet_get_output_channel_count(int32_t ctxId, int32_t bridgeId) {
  auto e = wajuce::getEngine(ctxId);
  return e ? e->getWorkletBridgeOutputChannelCount(bridgeId) : 0;
}

FFI_PLUGIN_EXPORT int32_t wajuce_worklet_get_read_pos(int32_t ctxId,
                                                      int32_t bridgeId,
                                                      int32_t direction,
                                                      int32_t channel) {
  auto state = getBridgeState(ctxId, bridgeId);
  auto buffers = state ? (direction == 0 ? state->toIsolate
                                         : state->fromIsolate)
                       : nullptr;
  auto *rb = buffers ? buffers->getChannel(channel) : nullptr;
  return rb ? rb->getReadPos() : 0;
}

FFI_PLUGIN_EXPORT int32_t wajuce_worklet_get_write_pos(int32_t ctxId,
                                                       int32_t bridgeId,
                                                       int32_t direction,
                                                       int32_t channel) {
  auto state = getBridgeState(ctxId, bridgeId);
  auto buffers = state ? (direction == 0 ? state->toIsolate
                                         : state->fromIsolate)
                       : nullptr;
  auto *rb = buffers ? buffers->getChannel(channel) : nullptr;
  return rb ? rb->getWritePos() : 0;
}

FFI_PLUGIN_EXPORT void wajuce_worklet_set_read_pos(int32_t ctxId,
                                                   int32_t bridgeId,
                                                   int32_t direction,
                                                   int32_t channel,
                                                   int32_t value) {
  auto state = getBridgeState(ctxId, bridgeId);
  auto buffers = state ? (direction == 0 ? state->toIsolate
                                         : state->fromIsolate)
                       : nullptr;
  if (auto *rb = buffers ? buffers->getChannel(channel) : nullptr) {
    rb->setReadPos(value);
  }
}

FFI_PLUGIN_EXPORT void wajuce_worklet_set_write_pos(int32_t ctxId,
                                                    int32_t bridgeId,
                                                    int32_t direction,
                                                    int32_t channel,
                                                    int32_t value) {
  auto state = getBridgeState(ctxId, bridgeId);
  auto buffers = state ? (direction == 0 ? state->toIsolate
                                         : state->fromIsolate)
                       : nullptr;
  if (auto *rb = buffers ? buffers->getChannel(channel) : nullptr) {
    rb->setWritePos(value);
  }
}

FFI_PLUGIN_EXPORT int32_t wajuce_worklet_get_capacity(int32_t ctxId,
                                                      int32_t bridgeId) {
  auto e = wajuce::getEngine(ctxId);
  return e ? e->getWorkletBridgeCapacity(bridgeId) : 0;
}

FFI_PLUGIN_EXPORT void wajuce_worklet_release_bridge(int32_t ctxId,
                                                     int32_t bridgeId) {
  if (auto e = wajuce::getEngine(ctxId)) {
    e->releaseWorkletBridge(bridgeId);
  }
}

FFI_PLUGIN_EXPORT int32_t wajuce_context_render(int32_t ctxId, float *outData,
                                                int32_t frames,
                                                int32_t channels) {
  auto e = wajuce::getEngine(ctxId);
  return e ? e->render(outData, frames, channels) : 0;
}

FFI_PLUGIN_EXPORT void wajuce_context_set_input_buffer(int32_t ctxId,
                                                       const float *inputData,
                                                       int32_t frames,
                                                       int32_t channels) {
  if (auto e = wajuce::getEngine(ctxId)) {
    e->setRealtimeInputInterleaved(inputData, frames, channels);
  }
}

static uint16_t readU16(const uint8_t *p) {
  return static_cast<uint16_t>(p[0] | (p[1] << 8));
}

static uint32_t readU32(const uint8_t *p) {
  return static_cast<uint32_t>(p[0] | (p[1] << 8) | (p[2] << 16) |
                               (p[3] << 24));
}

static uint16_t readBE16(const uint8_t *p) {
  return static_cast<uint16_t>((p[0] << 8) | p[1]);
}

static uint32_t readBE32(const uint8_t *p) {
  return static_cast<uint32_t>((p[0] << 24) | (p[1] << 16) | (p[2] << 8) |
                               p[3]);
}

static double readExtended80(const uint8_t *p) {
  const uint16_t expon = readBE16(p);
  uint64_t mantissa = 0;
  for (int i = 0; i < 8; ++i) {
    mantissa = (mantissa << 8) | p[2 + i];
  }
  if (expon == 0 && mantissa == 0) {
    return 0.0;
  }
  const int sign = (expon & 0x8000) ? -1 : 1;
  const int exp = (expon & 0x7FFF) - 16383;
  const double fraction =
      static_cast<double>(mantissa) / std::ldexp(1.0, 63);
  return sign * std::ldexp(fraction, exp);
}

static float decodeIntegerSample(const uint8_t *sample, int bits,
                                 bool littleEndian, bool unsigned8) {
  if (bits == 8) {
    if (unsigned8) {
      return (static_cast<int>(sample[0]) - 128) / 128.0f;
    }
    return static_cast<int8_t>(sample[0]) / 128.0f;
  }
  if (bits == 16) {
    const uint16_t raw = littleEndian ? readU16(sample) : readBE16(sample);
    return static_cast<int16_t>(raw) / 32768.0f;
  }
  if (bits == 24) {
    int32_t v = littleEndian ? (sample[0] | (sample[1] << 8) |
                                (sample[2] << 16))
                             : ((sample[0] << 16) | (sample[1] << 8) |
                                sample[2]);
    if (v & 0x800000) {
      v |= ~0xFFFFFF;
    }
    return v / 8388608.0f;
  }
  if (bits == 32) {
    const uint32_t raw = littleEndian ? readU32(sample) : readBE32(sample);
    return static_cast<int32_t>(raw) / 2147483648.0f;
  }
  return 0.0f;
}

static float decodeFloatSample(const uint8_t *sample, int bits,
                               bool littleEndian) {
  if (bits == 32) {
    const uint32_t raw = littleEndian ? readU32(sample) : readBE32(sample);
    float value = 0.0f;
    std::memcpy(&value, &raw, sizeof(float));
    return std::isfinite(value) ? value : 0.0f;
  }
  if (bits == 64) {
    uint64_t raw = 0;
    if (littleEndian) {
      for (int i = 7; i >= 0; --i) {
        raw = (raw << 8) | sample[i];
      }
    } else {
      for (int i = 0; i < 8; ++i) {
        raw = (raw << 8) | sample[i];
      }
    }
    double value = 0.0;
    std::memcpy(&value, &raw, sizeof(double));
    return std::isfinite(value) ? static_cast<float>(value) : 0.0f;
  }
  return 0.0f;
}

static int decodeWaveAudioData(const uint8_t *encodedData, int32_t len,
                               float *outData, int32_t *outFrames,
                               int32_t *outChannels, int32_t *outSr) {
  if (std::memcmp(encodedData, "RIFF", 4) != 0 ||
      std::memcmp(encodedData + 8, "WAVE", 4) != 0) {
    return -1;
  }

  uint16_t format = 0;
  uint16_t channels = 0;
  uint32_t sampleRate = 0;
  uint16_t bits = 0;
  const uint8_t *pcm = nullptr;
  uint32_t pcmBytes = 0;

  int offset = 12;
  while (offset + 8 <= len) {
    const uint8_t *chunk = encodedData + offset;
    const uint32_t size = readU32(chunk + 4);
    const int dataOffset = offset + 8;
    if (dataOffset + static_cast<int>(size) > len) {
      break;
    }
    if (std::memcmp(chunk, "fmt ", 4) == 0 && size >= 16) {
      format = readU16(encodedData + dataOffset);
      channels = readU16(encodedData + dataOffset + 2);
      sampleRate = readU32(encodedData + dataOffset + 4);
      bits = readU16(encodedData + dataOffset + 14);
      if (format == 0xFFFE && size >= 40) {
        format = readU16(encodedData + dataOffset + 24);
      }
    } else if (std::memcmp(chunk, "data", 4) == 0) {
      pcm = encodedData + dataOffset;
      pcmBytes = size;
    }
    offset = dataOffset + static_cast<int>(size) + (size & 1);
  }

  if (!pcm || channels == 0 || sampleRate == 0 || bits == 0) {
    return -1;
  }
  const int bytesPerSample = bits / 8;
  if (bytesPerSample <= 0 || pcmBytes < channels * bytesPerSample) {
    return -1;
  }
  const int frames = static_cast<int>(pcmBytes / (channels * bytesPerSample));
  *outFrames = frames;
  *outChannels = channels;
  *outSr = static_cast<int32_t>(sampleRate);
  if (!outData) {
    return 0;
  }

  for (int frame = 0; frame < frames; ++frame) {
    for (int ch = 0; ch < channels; ++ch) {
      const uint8_t *sample =
          pcm + static_cast<size_t>((frame * channels + ch) * bytesPerSample);
      float value = 0.0f;
      if (format == 3 && (bits == 32 || bits == 64)) {
        value = decodeFloatSample(sample, bits, true);
      } else if (format == 1) {
        value = decodeIntegerSample(sample, bits, true, bits == 8);
      } else {
        return -1;
      }
      outData[static_cast<size_t>(ch * frames + frame)] = value;
    }
  }
  return 0;
}

static int decodeAiffAudioData(const uint8_t *encodedData, int32_t len,
                               float *outData, int32_t *outFrames,
                               int32_t *outChannels, int32_t *outSr) {
  if (std::memcmp(encodedData, "FORM", 4) != 0 ||
      (std::memcmp(encodedData + 8, "AIFF", 4) != 0 &&
       std::memcmp(encodedData + 8, "AIFC", 4) != 0)) {
    return -1;
  }
  const bool aifc = std::memcmp(encodedData + 8, "AIFC", 4) == 0;
  uint16_t channels = 0;
  uint32_t frames = 0;
  uint16_t bits = 0;
  uint32_t sampleRate = 0;
  uint32_t compression = 0x4E4F4E45; // NONE
  const uint8_t *sound = nullptr;
  uint32_t soundBytes = 0;

  int offset = 12;
  while (offset + 8 <= len) {
    const uint8_t *chunk = encodedData + offset;
    const uint32_t size = readBE32(chunk + 4);
    const int dataOffset = offset + 8;
    if (dataOffset + static_cast<int>(size) > len) {
      break;
    }
    if (std::memcmp(chunk, "COMM", 4) == 0 && size >= (aifc ? 22u : 18u)) {
      channels = readBE16(encodedData + dataOffset);
      frames = readBE32(encodedData + dataOffset + 2);
      bits = readBE16(encodedData + dataOffset + 6);
      sampleRate = static_cast<uint32_t>(
          std::round(readExtended80(encodedData + dataOffset + 8)));
      if (aifc) {
        compression = readBE32(encodedData + dataOffset + 18);
      }
    } else if (std::memcmp(chunk, "SSND", 4) == 0 && size >= 8) {
      const uint32_t soundOffset = readBE32(encodedData + dataOffset);
      const int start = dataOffset + 8 + static_cast<int>(soundOffset);
      if (start <= dataOffset + static_cast<int>(size)) {
        sound = encodedData + start;
        soundBytes = static_cast<uint32_t>(dataOffset + size - start);
      }
    }
    offset = dataOffset + static_cast<int>(size) + (size & 1);
  }

  if (!sound || channels == 0 || frames == 0 || sampleRate == 0 || bits == 0) {
    return -1;
  }
  const bool littleEndian = compression == 0x736F7774; // sowt
  const bool floatingPoint =
      compression == 0x666C3332 || compression == 0x666C3634; // fl32/fl64
  if (compression != 0x4E4F4E45 && !littleEndian && !floatingPoint) {
    return -1;
  }
  const int bytesPerSample = bits / 8;
  if (bytesPerSample <= 0 ||
      soundBytes < frames * channels * static_cast<uint32_t>(bytesPerSample)) {
    return -1;
  }
  *outFrames = static_cast<int32_t>(frames);
  *outChannels = channels;
  *outSr = static_cast<int32_t>(sampleRate);
  if (!outData) {
    return 0;
  }
  for (uint32_t frame = 0; frame < frames; ++frame) {
    for (int ch = 0; ch < channels; ++ch) {
      const uint8_t *sample =
          sound + static_cast<size_t>((frame * channels + ch) * bytesPerSample);
      outData[static_cast<size_t>(ch * frames + frame)] =
          floatingPoint ? decodeFloatSample(sample, bits, false)
                        : decodeIntegerSample(sample, bits, littleEndian, false);
    }
  }
  return 0;
}

#if defined(__APPLE__)
struct MemoryAudioFile {
  const uint8_t *data = nullptr;
  int64_t len = 0;
};

static OSStatus memoryAudioReadProc(void *clientData, SInt64 position,
                                    UInt32 requestCount, void *buffer,
                                    UInt32 *actualCount) {
  auto *source = static_cast<MemoryAudioFile *>(clientData);
  if (!source || !source->data || !actualCount || position < 0 ||
      position >= source->len) {
    if (actualCount) {
      *actualCount = 0;
    }
    return noErr;
  }
  const auto available = static_cast<UInt32>(
      std::min<int64_t>(requestCount, source->len - position));
  if (available > 0 && buffer) {
    std::memcpy(buffer, source->data + position, available);
  }
  *actualCount = available;
  return noErr;
}

static SInt64 memoryAudioGetSizeProc(void *clientData) {
  auto *source = static_cast<MemoryAudioFile *>(clientData);
  return source ? source->len : 0;
}

static int decodeAppleAudioData(const uint8_t *encodedData, int32_t len,
                                float *outData, int32_t *outFrames,
                                int32_t *outChannels, int32_t *outSr) {
  MemoryAudioFile source{encodedData, len};
  AudioFileID fileId = nullptr;
  ExtAudioFileRef ext = nullptr;

  OSStatus status = AudioFileOpenWithCallbacks(
      &source, memoryAudioReadProc, nullptr, memoryAudioGetSizeProc, nullptr, 0,
      &fileId);
  if (status != noErr || !fileId) {
    return -1;
  }

  status = ExtAudioFileWrapAudioFileID(fileId, false, &ext);
  if (status != noErr || !ext) {
    AudioFileClose(fileId);
    return -1;
  }

  AudioStreamBasicDescription fileFormat{};
  UInt32 propertySize = sizeof(fileFormat);
  status = ExtAudioFileGetProperty(ext, kExtAudioFileProperty_FileDataFormat,
                                   &propertySize, &fileFormat);
  if (status != noErr || fileFormat.mChannelsPerFrame == 0 ||
      fileFormat.mSampleRate <= 0.0) {
    ExtAudioFileDispose(ext);
    return -1;
  }

  SInt64 frameCount = 0;
  propertySize = sizeof(frameCount);
  status = ExtAudioFileGetProperty(ext, kExtAudioFileProperty_FileLengthFrames,
                                   &propertySize, &frameCount);
  if (status != noErr || frameCount <= 0 ||
      frameCount > std::numeric_limits<int32_t>::max()) {
    ExtAudioFileDispose(ext);
    return -1;
  }

  const auto channels = static_cast<int32_t>(fileFormat.mChannelsPerFrame);
  const auto frames = static_cast<int32_t>(frameCount);
  const auto sampleRate = static_cast<int32_t>(std::round(fileFormat.mSampleRate));

  AudioStreamBasicDescription clientFormat{};
  clientFormat.mSampleRate = fileFormat.mSampleRate;
  clientFormat.mFormatID = kAudioFormatLinearPCM;
  clientFormat.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
  clientFormat.mBytesPerPacket = static_cast<UInt32>(channels * sizeof(float));
  clientFormat.mFramesPerPacket = 1;
  clientFormat.mBytesPerFrame = static_cast<UInt32>(channels * sizeof(float));
  clientFormat.mChannelsPerFrame = static_cast<UInt32>(channels);
  clientFormat.mBitsPerChannel = 32;

  status = ExtAudioFileSetProperty(ext, kExtAudioFileProperty_ClientDataFormat,
                                   sizeof(clientFormat), &clientFormat);
  if (status != noErr) {
    ExtAudioFileDispose(ext);
    return -1;
  }

  *outFrames = frames;
  *outChannels = channels;
  *outSr = sampleRate;
  if (!outData) {
    ExtAudioFileDispose(ext);
    return 0;
  }

  std::vector<float> interleaved(static_cast<size_t>(frames) * channels, 0.0f);
  int32_t offset = 0;
  while (offset < frames) {
    UInt32 framesToRead =
        static_cast<UInt32>(std::min<int32_t>(4096, frames - offset));
    AudioBufferList bufferList{};
    bufferList.mNumberBuffers = 1;
    bufferList.mBuffers[0].mNumberChannels = static_cast<UInt32>(channels);
    bufferList.mBuffers[0].mDataByteSize =
        framesToRead * static_cast<UInt32>(channels * sizeof(float));
    bufferList.mBuffers[0].mData =
        interleaved.data() + static_cast<size_t>(offset) * channels;

    status = ExtAudioFileRead(ext, &framesToRead, &bufferList);
    if (status != noErr || framesToRead == 0) {
      break;
    }
    offset += static_cast<int32_t>(framesToRead);
  }
  ExtAudioFileDispose(ext);

  if (offset != frames) {
    return -1;
  }
  for (int32_t frame = 0; frame < *outFrames; ++frame) {
    for (int32_t ch = 0; ch < channels; ++ch) {
      outData[static_cast<size_t>(ch) * (*outFrames) + frame] =
          interleaved[static_cast<size_t>(frame) * channels + ch];
    }
  }
  return 0;
}
#endif

FFI_PLUGIN_EXPORT int32_t wajuce_decode_audio_data(const uint8_t *encodedData,
                                                   int32_t len,
                                                   float *outData,
                                                   int32_t *outFrames,
                                                   int32_t *outChannels,
                                                   int32_t *outSr) {
  if (!encodedData || len < 44 || !outFrames || !outChannels || !outSr) {
    return -1;
  }
  if (len >= 12 && std::memcmp(encodedData, "RIFF", 4) == 0) {
    return decodeWaveAudioData(encodedData, len, outData, outFrames,
                               outChannels, outSr);
  }
  if (len >= 12 && std::memcmp(encodedData, "FORM", 4) == 0) {
    return decodeAiffAudioData(encodedData, len, outData, outFrames,
                               outChannels, outSr);
  }
#if defined(__APPLE__)
  return decodeAppleAudioData(encodedData, len, outData, outFrames, outChannels,
                              outSr);
#endif
  return -1;
}

#if defined(WAJUCE_USE_RTMIDI) && WAJUCE_USE_RTMIDI
static wajuce_midi_callback_t gMidiCallback = nullptr;
static std::mutex gMidiMtx;
static std::unordered_map<int32_t, std::unique_ptr<RtMidiIn>> gMidiIns;
static std::unordered_map<int32_t, std::unique_ptr<RtMidiOut>> gMidiOuts;

static void midiInCallback(double timestamp, std::vector<unsigned char> *msg,
                           void *userData) {
  if (!gMidiCallback || !msg) {
    return;
  }
  const auto index = static_cast<int32_t>(reinterpret_cast<intptr_t>(userData));
  gMidiCallback(index, msg->data(), static_cast<int32_t>(msg->size()),
                timestamp);
}
#endif

FFI_PLUGIN_EXPORT int32_t wajuce_midi_get_port_count(int32_t type) {
#if defined(WAJUCE_USE_RTMIDI) && WAJUCE_USE_RTMIDI
  try {
    if (type == 0) {
      RtMidiIn in;
      return static_cast<int32_t>(in.getPortCount());
    }
    RtMidiOut out;
    return static_cast<int32_t>(out.getPortCount());
  } catch (...) {
    return 0;
  }
#else
  (void)type;
  return 0;
#endif
}

FFI_PLUGIN_EXPORT void wajuce_midi_get_port_name(int32_t type, int32_t index,
                                                 char *buffer,
                                                 int32_t maxLen) {
  if (!buffer || maxLen <= 0) {
    return;
  }
  buffer[0] = '\0';
#if defined(WAJUCE_USE_RTMIDI) && WAJUCE_USE_RTMIDI
  try {
    std::string name =
        type == 0 ? RtMidiIn().getPortName(index)
                  : RtMidiOut().getPortName(index);
    std::snprintf(buffer, static_cast<size_t>(maxLen), "%s", name.c_str());
  } catch (...) {
  }
#else
  (void)type;
  (void)index;
#endif
}

FFI_PLUGIN_EXPORT void wajuce_midi_port_open(int32_t type, int32_t index) {
#if defined(WAJUCE_USE_RTMIDI) && WAJUCE_USE_RTMIDI
  std::lock_guard<std::mutex> lock(gMidiMtx);
  try {
    if (type == 0) {
      auto input = std::make_unique<RtMidiIn>();
      input->openPort(index);
      input->ignoreTypes(false, false, false);
      input->setCallback(&midiInCallback,
                         reinterpret_cast<void *>(static_cast<intptr_t>(index)));
      gMidiIns[index] = std::move(input);
    } else {
      auto output = std::make_unique<RtMidiOut>();
      output->openPort(index);
      gMidiOuts[index] = std::move(output);
    }
  } catch (...) {
  }
#else
  (void)type;
  (void)index;
#endif
}

FFI_PLUGIN_EXPORT void wajuce_midi_port_close(int32_t type, int32_t index) {
#if defined(WAJUCE_USE_RTMIDI) && WAJUCE_USE_RTMIDI
  std::lock_guard<std::mutex> lock(gMidiMtx);
  if (type == 0) {
    gMidiIns.erase(index);
  } else {
    gMidiOuts.erase(index);
  }
#else
  (void)type;
  (void)index;
#endif
}

FFI_PLUGIN_EXPORT void wajuce_midi_output_send(int32_t index,
                                               const uint8_t *data,
                                               int32_t len, double) {
#if defined(WAJUCE_USE_RTMIDI) && WAJUCE_USE_RTMIDI
  if (!data || len <= 0) {
    return;
  }
  std::lock_guard<std::mutex> lock(gMidiMtx);
  auto it = gMidiOuts.find(index);
  if (it == gMidiOuts.end()) {
    return;
  }
  std::vector<unsigned char> msg(data, data + len);
  try {
    it->second->sendMessage(&msg);
  } catch (...) {
  }
#else
  (void)index;
  (void)data;
  (void)len;
#endif
}

FFI_PLUGIN_EXPORT void wajuce_midi_set_callback(wajuce_midi_callback_t cb) {
#if defined(WAJUCE_USE_RTMIDI) && WAJUCE_USE_RTMIDI
  gMidiCallback = cb;
#else
  (void)cb;
#endif
}

FFI_PLUGIN_EXPORT void wajuce_midi_dispose() {
#if defined(WAJUCE_USE_RTMIDI) && WAJUCE_USE_RTMIDI
  std::lock_guard<std::mutex> lock(gMidiMtx);
  gMidiIns.clear();
  gMidiOuts.clear();
  gMidiCallback = nullptr;
#endif
}

} // extern "C"
