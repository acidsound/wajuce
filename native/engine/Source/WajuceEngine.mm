/**
 * WajuceEngine.cpp — Implementation of the JUCE audio engine.
 */

#include "WajuceEngine.h"
#include <cassert>
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

std::unordered_map<int32_t, std::unique_ptr<Engine>> g_engines;
std::mutex g_engineMtx;
int32_t g_nextCtxId = 1;

std::unordered_map<int32_t, std::unique_ptr<MidiInputProxy>> g_midiInputs;
std::unordered_map<int32_t, std::unique_ptr<juce::MidiOutput>> g_midiOutputs;
std::mutex g_midiMtx;

Engine *findEngineForNode(int32_t nodeId) {
  std::lock_guard<std::mutex> lock(g_engineMtx);
  for (auto &[id, engine] : g_engines) {
    if (engine->getRegistry().get(nodeId))
      return engine.get();
  }
  return nullptr;
}

static wajuce::Engine *getEngine(int32_t id) {
  auto it = wajuce::g_engines.find(id);
  return it != wajuce::g_engines.end() ? it->second.get() : nullptr;
}

// ============================================================================
// Engine Implementation
// ============================================================================

Engine::Engine(double sr, int bs, int inCh, int outCh)
    : sampleRate(sr), bufferSize(bs) {
  WA_LOG("[wajuce] Engine::Engine sr=%f, bs=%d, in=%d, out=%d", sr, bs, inCh,
         outCh);
  graph = std::make_unique<juce::AudioProcessorGraph>();
  graph->setPlayConfigDetails(inCh, outCh, sampleRate, bufferSize);
  graph->prepareToPlay(sampleRate, bufferSize);

  inputNode = graph->addNode(
      std::make_unique<juce::AudioProcessorGraph::AudioGraphIOProcessor>(
          juce::AudioProcessorGraph::AudioGraphIOProcessor::audioInputNode));
  outputNode = graph->addNode(
      std::make_unique<juce::AudioProcessorGraph::AudioGraphIOProcessor>(
          juce::AudioProcessorGraph::AudioGraphIOProcessor::audioOutputNode));

#ifdef JUCE_IOS
  // Explicitly configure AVAudioSession for PlayAndRecord with default to
  // speaker
  auto session = [AVAudioSession sharedInstance];
  NSError *error = nil;
  [session setCategory:AVAudioSessionCategoryPlayAndRecord
           withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker |
                       AVAudioSessionCategoryOptionAllowBluetooth |
                       AVAudioSessionCategoryOptionMixWithOthers
                 error:&error];
  if (error) {
    WA_LOG("[wajuce] AVAudioSession error: %s",
           [[error localizedDescription] UTF8String]);
  }
  [session setActive:YES error:nil];
#endif

  auto err = deviceManager.initialiseWithDefaultDevices(inCh, outCh);
  deviceManager.addAudioCallback(&sourcePlayer);
  sourcePlayer.setSource(this);
}

Engine::~Engine() {
  sourcePlayer.setSource(nullptr);
  deviceManager.removeAudioCallback(&sourcePlayer);
  graph.reset();
}

void Engine::prepareToPlay(int samples, double sr) {
  WA_LOG("[wajuce] Engine::prepareToPlay sr=%f, bs=%d", sr, samples);
  sampleRate = sr;
  bufferSize = samples;
  int inCh = graph->getMainBusNumInputChannels();
  int outCh = graph->getMainBusNumOutputChannels();
  graph->setPlayConfigDetails(inCh, outCh, sr, samples);
  graph->prepareToPlay(sr, samples);
}

void Engine::releaseResources() { graph->releaseResources(); }

void Engine::getNextAudioBlock(const juce::AudioSourceChannelInfo &info) {
  if (state.load() != 1) {
    info.clearActiveBufferRegion();
    return;
  }

  double now = currentTime.load(std::memory_order_relaxed);
  processAutomation(now, sampleRate, info.numSamples);

  // Use sub-buffer to respect startSample and numSamples
  juce::AudioBuffer<float> proxy(info.buffer->getArrayOfWritePointers(),
                                 info.buffer->getNumChannels(),
                                 info.startSample, info.numSamples);
  // proxy.clear(); // DO NOT CLEAR - We need physical input from info.buffer
  juce::MidiBuffer midi;
  graph->processBlock(proxy, midi);

  totalSamplesProcessed += info.numSamples;
  currentTime.store((double)totalSamplesProcessed / sampleRate,
                    std::memory_order_relaxed);
}

void Engine::resume() { state = 1; }
void Engine::suspend() { state = 0; }
void Engine::close() {
  state = 2;
  sourcePlayer.setSource(nullptr);
  deviceManager.removeAudioCallback(&sourcePlayer);
}

// ============================================================================
// Node Factory
// ============================================================================

int32_t Engine::addToGraph(NodeType type,
                           std::unique_ptr<juce::AudioProcessor> proc) {
  std::lock_guard<std::mutex> lock(graphMtx);
  proc->setPlayConfigDetails(2, 2, sampleRate, bufferSize);
  proc->prepareToPlay(sampleRate, bufferSize);

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
  auto node = graph->addNode(std::move(proc));
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
    auto it = idToGraphNode.find(id);
    if (it != idToGraphNode.end()) {
      graph->addConnection({{inputNode->nodeID, 0}, {it->second, 0}});
      graph->addConnection({{inputNode->nodeID, 1}, {it->second, 1}});
    }
  }
  return id;
}
int32_t Engine::createMediaStreamDestination() {
  return addToGraph(NodeType::MediaStreamDestination,
                    std::make_unique<MediaStreamDestinationProcessor>());
}

int32_t Engine::createWorkletBridge(int32_t inputs, int32_t outputs) {
  return addToGraph(NodeType::WorkletBridge,
                    std::make_unique<WorkletBridgeProcessor>(inputs, outputs));
}

void Engine::removeNode(int32_t nodeId) {
  std::lock_guard<std::mutex> lock(graphMtx);
  auto it = idToGraphNode.find(nodeId);
  if (it != idToGraphNode.end()) {
    graph->removeNode(it->second);
    idToGraphNode.erase(it);
  }

  // Cleanup feedback bridges involving this node
  for (auto fit = feedbackConnections.begin();
       fit != feedbackConnections.end();) {
    if (fit->srcId == nodeId || fit->dstId == nodeId) {
      graph->removeNode(fit->sender);
      graph->removeNode(fit->receiver);
      fit = feedbackConnections.erase(fit);
    } else {
      ++fit;
    }
  }

  registry.remove(nodeId);
}

// Batch creation for Machine Voice
void Engine::createMachineVoice(int32_t *resultIds) {
  std::lock_guard<std::mutex> lock(graphMtx);

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
  const auto sr = sampleRate;
  const auto bs = bufferSize;

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
  delay->delayTime = 0.5f; // 1.0 might be too long default
  delayWet->gain = 0.0f;

  // Add to Graph
  auto nOsc = graph->addNode(std::move(osc));
  auto nFilter = graph->addNode(std::move(filter));
  auto nGain = graph->addNode(std::move(gain));
  auto nPanner = graph->addNode(std::move(panner));
  auto nDelay = graph->addNode(std::move(delay));
  auto nDelayFb = graph->addNode(std::move(delayFb));
  auto nDelayWet = graph->addNode(std::move(delayWet));

  // INTERNAL Connections (No output connection yet - Lazy)
  // Osc -> Filter -> Gain -> Panner
  graph->addConnection({{nOsc->nodeID, 0}, {nFilter->nodeID, 0}});
  graph->addConnection({{nFilter->nodeID, 0}, {nGain->nodeID, 0}});
  graph->addConnection({{nGain->nodeID, 0}, {nPanner->nodeID, 0}});

  // Gain -> Delay path
  graph->addConnection({{nGain->nodeID, 0}, {nDelay->nodeID, 0}});
  graph->addConnection({{nDelay->nodeID, 0}, {nDelayWet->nodeID, 0}});

  // Delay Feedback loop
  graph->addConnection({{nDelay->nodeID, 0}, {nDelayFb->nodeID, 0}});
  // graph->addConnection({{nDelayFb->nodeID, 0}, {nDelay->nodeID, 0}}); //
  // ILLEGAL DIRECT CYCLE - Causes O(N^2) validation overhead

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
}

void Engine::connect(int32_t srcId, int32_t dstId, int output, int input) {
  std::lock_guard<std::mutex> lock(graphMtx);
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
    using NodeAndChannel = juce::AudioProcessorGraph::NodeAndChannel;

    // Pre-check for cycle using JUCE's isAnInputTo
    bool wouldCycle = graph->isAnInputTo(dstNodeId, srcNodeId);

    if (!wouldCycle) {
      bool ok = graph->addConnection({NodeAndChannel{srcNodeId, outPort},
                                      NodeAndChannel{dstNodeId, inPort}});
      if (ok)
        return true;
    }

    // Cycle detected! Implement FeedbackBridge (1-block delay)
    WA_LOG("[wajuce] Cycle detected: %d:%d -> %d:%d. Creating bridge.", srcId,
           outPort, dstId, inPort);

    auto sharedBuf = std::make_shared<juce::AudioBuffer<float>>(2, bufferSize);
    sharedBuf->clear();

    auto senderProc = std::make_unique<FeedbackSenderProcessor>(sharedBuf);
    senderProc->setPlayConfigDetails(2, 2, sampleRate, bufferSize);
    senderProc->prepareToPlay(sampleRate, bufferSize);
    auto receiverProc = std::make_unique<FeedbackReceiverProcessor>(sharedBuf);
    receiverProc->setPlayConfigDetails(2, 2, sampleRate, bufferSize);
    receiverProc->prepareToPlay(sampleRate, bufferSize);

    auto senderNode = graph->addNode(std::move(senderProc));
    auto receiverNode = graph->addNode(std::move(receiverProc));
    if (!senderNode || !receiverNode) {
      WA_LOG("[wajuce] FeedbackBridge: addNode failed.");
      return false;
    }
    auto senderNID = senderNode->nodeID;
    auto receiverNID = receiverNode->nodeID;

    bool c1 = graph->addConnection({NodeAndChannel{srcNodeId, outPort},
                                    NodeAndChannel{senderNID, outPort % 2}});
    bool c2 = graph->addConnection({NodeAndChannel{receiverNID, inPort % 2},
                                    NodeAndChannel{dstNodeId, inPort}});

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
      graph->removeNode(senderNID);
      graph->removeNode(receiverNID);
      return false;
    }
  };

  auto srcEntry = registry.get(srcId);
  auto dstEntry = registry.get(dstId);

  bool isSplitter = srcEntry && srcEntry->type == NodeType::ChannelSplitter;
  bool isMerger = dstEntry && dstEntry->type == NodeType::ChannelMerger;

  if (isSplitter || isMerger) {
    attemptConnect(output, input);
  } else {
    // Legacy/Default: Connect all matching channels (up to 32)
    // Starting from the specified output/input indices.
    for (int i = 0; i < 32; ++i) {
      attemptConnect(output + i, input + i);
    }
  }
}

void Engine::disconnect(int32_t srcId, int32_t dstId) {
  std::lock_guard<std::mutex> lock(graphMtx);
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
  graph->removeConnection({{src, 0}, {dst, 0}});
  graph->removeConnection({{src, 1}, {dst, 1}});

  // Cleanup feedback bridges between these specific nodes
  for (auto fit = feedbackConnections.begin();
       fit != feedbackConnections.end();) {
    if (fit->srcId == srcId && fit->dstId == dstId) {
      graph->removeNode(fit->sender);
      graph->removeNode(fit->receiver);
      fit = feedbackConnections.erase(fit);
    } else {
      ++fit;
    }
  }
}

void Engine::disconnectAll(int32_t srcId) {
  std::lock_guard<std::mutex> lock(graphMtx);
  auto it = idToGraphNode.find(srcId);
  if (it == idToGraphNode.end())
    return;
  juce::AudioProcessorGraph::NodeID src = it->second;
  auto connections = graph->getConnections();
  for (auto &conn : connections) {
    if (conn.source.nodeID == src)
      graph->removeConnection(conn);
  }

  // Cleanup all feedback bridges originating from this node
  for (auto fit = feedbackConnections.begin();
       fit != feedbackConnections.end();) {
    if (fit->srcId == srcId) {
      graph->removeNode(fit->sender);
      graph->removeNode(fit->receiver);
      fit = feedbackConnections.erase(fit);
    } else {
      ++fit;
    }
  }
}

ParamTimeline *Engine::getOrCreateTimeline(int32_t nodeId, const char *param) {
  auto *entry = registry.get(nodeId);
  return entry ? entry->getOrCreateTimeline(param) : nullptr;
}

void Engine::processAutomation(double startTime, double sr, int numSamples) {
  std::lock_guard<std::recursive_mutex> lock(registry.getMutex());
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
          g->sampleAccurateGains.assign(numSamples, g->gain.load());
          g->gain = tl_pair.second->processBlock(startTime, sr, numSamples,
                                                 g->sampleAccurateGains.data());
          g->isAutomated = true;
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
          d->sampleAccurateDelayTimes.assign(numSamples, d->delayTime.load());
          d->delayTime = tl_pair.second->processBlock(
              startTime, sr, numSamples, d->sampleAccurateDelayTimes.data());
          d->isAutomated = true;
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
  paramSet(nodeId, param, v);
  auto *tl = getOrCreateTimeline(nodeId, param);
  if (tl)
    tl->setValueAtTime(v, t);
}
void Engine::paramLinearRamp(int32_t nid, const char *p, float v, double te) {
  auto *tl = getOrCreateTimeline(nid, p);
  if (tl)
    tl->linearRampToValueAtTime(v, te);
}
void Engine::paramExpRamp(int nid, const char *p, float v, double te) {
  auto *tl = getOrCreateTimeline(nid, p);
  if (tl)
    tl->exponentialRampToValueAtTime(v, te);
}
void Engine::paramSetTarget(int nid, const char *p, float tgt, double ts,
                            float tc) {
  auto *tl = getOrCreateTimeline(nid, p);
  if (tl)
    tl->setTargetAtTime(tgt, ts, tc);
}
void Engine::paramCancel(int nid, const char *p, double tc) {
  auto *tl = getOrCreateTimeline(nid, p);
  if (tl)
    tl->cancelScheduledValues(tc);
}

void Engine::oscSetType(int32_t nodeId, int type) {
  auto *entry = registry.get(nodeId);
  if (entry && entry->type == NodeType::Oscillator)
    entry->asOsc()->type = type;
}
void Engine::oscStart(int32_t nodeId, double when) {
  auto *entry = registry.get(nodeId);
  if (entry && entry->type == NodeType::Oscillator)
    entry->asOsc()->start(when);
}
void Engine::oscStop(int32_t nid, double w) {
  auto *entry = registry.get(nid);
  if (entry && entry->type == NodeType::Oscillator)
    entry->asOsc()->stop(w);
}

void Engine::oscSetPeriodicWave(int32_t nid, const float *real,
                                const float *imag, int32_t len) {
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
  auto *entry = registry.get(nid);
  if (entry && entry->type == NodeType::BiquadFilter)
    entry->asFilter()->filterType = type;
}

void Engine::bufferSourceSetBuffer(int32_t nid, const float *d, int f, int c,
                                   int s) {
  auto *entry = registry.get(nid);
  if (entry && entry->type == NodeType::BufferSource)
    entry->asBufferSource()->setBuffer(d, f, c, s);
}
void Engine::bufferSourceStart(int32_t nid, double w) {
  auto *entry = registry.get(nid);
  if (entry && entry->type == NodeType::BufferSource)
    entry->asBufferSource()->start(w);
}
void Engine::bufferSourceStop(int32_t nid, double w) {
  auto *entry = registry.get(nid);
  if (entry && entry->type == NodeType::BufferSource)
    entry->asBufferSource()->stop(w);
}
void Engine::bufferSourceSetLoop(int32_t nid, bool l) {
  auto *entry = registry.get(nid);
  if (entry && entry->type == NodeType::BufferSource)
    entry->asBufferSource()->setLoop(l);
}

void Engine::analyserSetFftSize(int32_t nid, int32_t s) {
  auto *entry = registry.get(nid);
  if (entry && entry->type == NodeType::Analyser)
    entry->asAnalyser()->setFftSize(s);
}
void Engine::analyserGetByteFreqData(int32_t nid, uint8_t *d, int l) {
  auto *entry = registry.get(nid);
  if (entry && entry->type == NodeType::Analyser)
    entry->asAnalyser()->getByteFrequencyData(d, l);
}
void Engine::analyserGetByteTimeData(int32_t nid, uint8_t *d, int l) {
  auto *entry = registry.get(nid);
  if (entry && entry->type == NodeType::Analyser)
    entry->asAnalyser()->getByteTimeDomainData(d, l);
}
void Engine::analyserGetFloatFreqData(int32_t nid, float *d, int l) {
  auto *entry = registry.get(nid);
  if (entry && entry->type == NodeType::Analyser)
    entry->asAnalyser()->getFloatFrequencyData(d, l);
}
void Engine::analyserGetFloatTimeData(int32_t nid, float *d, int l) {
  auto *entry = registry.get(nid);
  if (entry && entry->type == NodeType::Analyser)
    entry->asAnalyser()->getFloatTimeDomainData(d, l);
}

void Engine::waveShaperSetCurve(int32_t nid, const float *d, int l) {
  auto *entry = registry.get(nid);
  if (entry && entry->type == NodeType::WaveShaper)
    entry->asWaveShaper()->setCurve(d, l);
}
void Engine::waveShaperSetOversample(int32_t nid, int t) {
  auto *entry = registry.get(nid);
  if (entry && entry->type == NodeType::WaveShaper)
    entry->asWaveShaper()->setOversample(t);
}

} // namespace wajuce

extern "C" {
using namespace wajuce;
FFI_PLUGIN_EXPORT int32_t wajuce_context_create(int32_t sr, int32_t bs,
                                                int32_t inCh, int32_t outCh) {
  std::lock_guard<std::mutex> lock(wajuce::g_engineMtx);
  auto engine = std::make_unique<wajuce::Engine>((double)sr, bs, inCh, outCh);
  int32_t id = wajuce::g_nextCtxId++;
  wajuce::g_engines[id] = std::move(engine);
  return id;
}
FFI_PLUGIN_EXPORT void wajuce_context_destroy(int32_t id) {
  std::lock_guard<std::mutex> lock(wajuce::g_engineMtx);
  wajuce::g_engines.erase(id);
}
FFI_PLUGIN_EXPORT double wajuce_context_get_time(int32_t id) {
  auto *e = getEngine(id);
  return e ? e->getCurrentTime() : 0.0;
}
FFI_PLUGIN_EXPORT double wajuce_context_get_sample_rate(int32_t id) {
  auto *e = getEngine(id);
  return e ? e->getSampleRate() : 44100.0;
}
FFI_PLUGIN_EXPORT int32_t wajuce_context_get_state(int32_t id) {
  auto *e = getEngine(id);
  return e ? e->getState() : 2;
}
FFI_PLUGIN_EXPORT void wajuce_context_resume(int32_t id) {
  auto *e = getEngine(id);
  if (e)
    e->resume();
}
FFI_PLUGIN_EXPORT void wajuce_context_suspend(int32_t id) {
  auto *e = getEngine(id);
  if (e)
    e->suspend();
}
FFI_PLUGIN_EXPORT void wajuce_context_close(int32_t id) {
  auto *e = getEngine(id);
  if (e)
    e->close();
}
FFI_PLUGIN_EXPORT int32_t wajuce_context_get_destination_id(int32_t id) {
  auto *e = getEngine(id);
  return e ? e->getDestinationId() : 0;
}
FFI_PLUGIN_EXPORT void wajuce_create_machine_voice(int32_t ctx_id,
                                                   int32_t *result_ids) {
  auto *engine = wajuce::getEngine(ctx_id);
  if (engine)
    engine->createMachineVoice(result_ids);
}

FFI_PLUGIN_EXPORT void wajuce_context_remove_node(int32_t cid, int32_t nid) {
  auto *e = getEngine(cid);
  if (e)
    e->removeNode(nid);
}
FFI_PLUGIN_EXPORT int32_t wajuce_create_gain(int32_t id) {
  auto *e = getEngine(id);
  return e ? e->createGain() : -1;
}
FFI_PLUGIN_EXPORT int32_t wajuce_create_oscillator(int32_t id) {
  auto *e = getEngine(id);
  return e ? e->createOscillator() : -1;
}
FFI_PLUGIN_EXPORT int32_t wajuce_create_biquad_filter(int32_t id) {
  auto *e = getEngine(id);
  return e ? e->createBiquadFilter() : -1;
}
FFI_PLUGIN_EXPORT int32_t wajuce_create_compressor(int32_t id) {
  auto *e = getEngine(id);
  return e ? e->createCompressor() : -1;
}
FFI_PLUGIN_EXPORT int32_t wajuce_create_delay(int32_t id, float d) {
  auto *e = getEngine(id);
  return e ? e->createDelay(d) : -1;
}
FFI_PLUGIN_EXPORT int32_t wajuce_create_buffer_source(int32_t id) {
  auto *e = getEngine(id);
  return e ? e->createBufferSource() : -1;
}
FFI_PLUGIN_EXPORT int32_t wajuce_create_analyser(int32_t id) {
  auto *e = getEngine(id);
  return e ? e->createAnalyser() : -1;
}
FFI_PLUGIN_EXPORT int32_t wajuce_create_stereo_panner(int32_t id) {
  auto *e = getEngine(id);
  return e ? e->createStereoPanner() : -1;
}
FFI_PLUGIN_EXPORT int32_t wajuce_create_wave_shaper(int32_t id) {
  auto *e = getEngine(id);
  return e ? e->createWaveShaper() : -1;
}
FFI_PLUGIN_EXPORT int32_t wajuce_create_media_stream_source(int32_t id) {
  auto *e = getEngine(id);
  return e ? e->createMediaStreamSource() : -1;
}
FFI_PLUGIN_EXPORT int32_t wajuce_create_media_stream_destination(int32_t id) {
  auto *e = getEngine(id);
  return e ? e->createMediaStreamDestination() : -1;
}
FFI_PLUGIN_EXPORT int32_t wajuce_create_worklet_bridge(int32_t id,
                                                       int32_t inputs,
                                                       int32_t outputs) {
  auto *e = getEngine(id);
  return e ? e->createWorkletBridge(inputs, outputs) : -1;
}

FFI_PLUGIN_EXPORT float *wajuce_worklet_get_buffer_ptr(int32_t bridge_id,
                                                       int32_t direction,
                                                       int32_t channel) {
  auto *e = wajuce::findEngineForNode(bridge_id);
  if (!e)
    return nullptr;
  auto *node = e->getRegistry().get(bridge_id);
  if (!node || node->type != wajuce::NodeType::WorkletBridge)
    return nullptr;
  auto *rb = (direction == 0)
                 ? node->asWorkletBridge()->toIsolate->getChannel(channel)
                 : node->asWorkletBridge()->fromIsolate->getChannel(channel);
  return rb ? rb->getBufferRawPtr() : nullptr;
}

FFI_PLUGIN_EXPORT int32_t *wajuce_worklet_get_read_pos_ptr(int32_t bridge_id,
                                                           int32_t direction,
                                                           int32_t channel) {
  auto *e = wajuce::findEngineForNode(bridge_id);
  if (!e)
    return nullptr;
  auto *node = e->getRegistry().get(bridge_id);
  if (!node || node->type != wajuce::NodeType::WorkletBridge)
    return nullptr;
  auto *rb = (direction == 0)
                 ? node->asWorkletBridge()->toIsolate->getChannel(channel)
                 : node->asWorkletBridge()->fromIsolate->getChannel(channel);
  return rb ? rb->getReadPosPtr() : nullptr;
}

FFI_PLUGIN_EXPORT int32_t *wajuce_worklet_get_write_pos_ptr(int32_t bridge_id,
                                                            int32_t direction,
                                                            int32_t channel) {
  auto *e = wajuce::findEngineForNode(bridge_id);
  if (!e)
    return nullptr;
  auto *node = e->getRegistry().get(bridge_id);
  if (!node || node->type != wajuce::NodeType::WorkletBridge)
    return nullptr;
  auto *rb = (direction == 0)
                 ? node->asWorkletBridge()->toIsolate->getChannel(channel)
                 : node->asWorkletBridge()->fromIsolate->getChannel(channel);
  return rb ? rb->getWritePosPtr() : nullptr;
}

FFI_PLUGIN_EXPORT int32_t wajuce_worklet_get_capacity(int32_t bridge_id) {
  auto *e = wajuce::findEngineForNode(bridge_id);
  if (!e)
    return 0;
  auto *node = e->getRegistry().get(bridge_id);
  if (!node || node->type != wajuce::NodeType::WorkletBridge)
    return 0;
  return node->asWorkletBridge()->toIsolate->getChannel(0)->getCapacity();
}
FFI_PLUGIN_EXPORT int32_t wajuce_create_channel_splitter(int32_t id,
                                                         int32_t outputs) {
  auto *e = getEngine(id);
  return e ? e->createChannelSplitter(outputs) : -1;
}
FFI_PLUGIN_EXPORT int32_t wajuce_create_channel_merger(int32_t id,
                                                       int32_t inputs) {
  auto *e = getEngine(id);
  return e ? e->createChannelMerger(inputs) : -1;
}

FFI_PLUGIN_EXPORT void wajuce_connect(int32_t cid, int32_t sid, int32_t did,
                                      int32_t o, int32_t i) {
  auto *e = getEngine(cid);
  if (e)
    e->connect(sid, did, o, i);
}
FFI_PLUGIN_EXPORT void wajuce_disconnect(int32_t cid, int32_t sid,
                                         int32_t did) {
  auto *e = getEngine(cid);
  if (e)
    e->disconnect(sid, did);
}
FFI_PLUGIN_EXPORT void wajuce_disconnect_all(int32_t cid, int32_t sid) {
  auto *e = getEngine(cid);
  if (e)
    e->disconnectAll(sid);
}

FFI_PLUGIN_EXPORT void wajuce_param_set(int32_t nid, const char *p, float v) {
  auto *e = wajuce::findEngineForNode(nid);
  if (e)
    e->paramSet(nid, p, v);
}
FFI_PLUGIN_EXPORT void wajuce_param_set_at_time(int32_t nid, const char *p,
                                                float v, double t) {
  auto *e = wajuce::findEngineForNode(nid);
  if (e)
    e->paramSetAtTime(nid, p, v, t);
}
FFI_PLUGIN_EXPORT void wajuce_param_linear_ramp(int32_t nid, const char *p,
                                                float v, double te) {
  auto *e = wajuce::findEngineForNode(nid);
  if (e)
    e->paramLinearRamp(nid, p, v, te);
}
FFI_PLUGIN_EXPORT void wajuce_param_exp_ramp(int32_t nid, const char *p,
                                             float v, double te) {
  auto *e = wajuce::findEngineForNode(nid);
  if (e)
    e->paramExpRamp(nid, p, v, te);
}
FFI_PLUGIN_EXPORT void wajuce_param_set_target(int32_t nid, const char *p,
                                               float tgt, double ts, float tc) {
  auto *e = wajuce::findEngineForNode(nid);
  if (e)
    e->paramSetTarget(nid, p, tgt, ts, tc);
}
FFI_PLUGIN_EXPORT void wajuce_param_cancel(int32_t nid, const char *p,
                                           double tc) {
  auto *e = wajuce::findEngineForNode(nid);
  if (e)
    e->paramCancel(nid, p, tc);
}

FFI_PLUGIN_EXPORT void wajuce_osc_set_type(int32_t nid, int32_t t) {
  auto *e = wajuce::findEngineForNode(nid);
  if (e)
    e->oscSetType(nid, t);
}
FFI_PLUGIN_EXPORT void wajuce_osc_start(int32_t nid, double w) {
  auto *e = wajuce::findEngineForNode(nid);
  if (e)
    e->oscStart(nid, w);
}
FFI_PLUGIN_EXPORT void wajuce_osc_stop(int32_t nid, double w) {
  auto *e = wajuce::findEngineForNode(nid);
  if (e)
    e->oscStop(nid, w);
}
FFI_PLUGIN_EXPORT void wajuce_osc_set_periodic_wave(int32_t nid,
                                                    const float *real,
                                                    const float *imag,
                                                    int32_t len) {
  auto *e = wajuce::findEngineForNode(nid);
  if (e)
    e->oscSetPeriodicWave(nid, real, imag, len);
}

FFI_PLUGIN_EXPORT void wajuce_filter_set_type(int32_t nid, int32_t t) {
  auto *e = wajuce::findEngineForNode(nid);
  if (e)
    e->filterSetType(nid, t);
}
FFI_PLUGIN_EXPORT void wajuce_buffer_source_set_buffer(int32_t nid,
                                                       const float *d,
                                                       int32_t f, int32_t c,
                                                       int32_t s) {
  auto *e = wajuce::findEngineForNode(nid);
  if (e)
    e->bufferSourceSetBuffer(nid, d, f, c, s);
}
FFI_PLUGIN_EXPORT void wajuce_buffer_source_start(int32_t nid, double w) {
  auto *e = wajuce::findEngineForNode(nid);
  if (e)
    e->bufferSourceStart(nid, w);
}
FFI_PLUGIN_EXPORT void wajuce_buffer_source_stop(int32_t nid, double w) {
  auto *e = wajuce::findEngineForNode(nid);
  if (e)
    e->bufferSourceStop(nid, w);
}
FFI_PLUGIN_EXPORT void wajuce_buffer_source_set_loop(int32_t nid, int32_t l) {
  auto *e = wajuce::findEngineForNode(nid);
  if (e)
    e->bufferSourceSetLoop(nid, l != 0);
}

FFI_PLUGIN_EXPORT void wajuce_analyser_set_fft_size(int32_t nid, int32_t s) {
  auto *e = wajuce::findEngineForNode(nid);
  if (e)
    e->analyserSetFftSize(nid, s);
}
FFI_PLUGIN_EXPORT void wajuce_analyser_get_byte_freq(int32_t nid, uint8_t *d,
                                                     int32_t l) {
  auto *e = wajuce::findEngineForNode(nid);
  if (e)
    e->analyserGetByteFreqData(nid, d, l);
}
FFI_PLUGIN_EXPORT void wajuce_analyser_get_byte_time(int32_t nid, uint8_t *d,
                                                     int32_t l) {
  auto *e = wajuce::findEngineForNode(nid);
  if (e)
    e->analyserGetByteTimeData(nid, d, l);
}
FFI_PLUGIN_EXPORT void wajuce_analyser_get_float_freq(int32_t nid, float *d,
                                                      int32_t l) {
  auto *e = wajuce::findEngineForNode(nid);
  if (e)
    e->analyserGetFloatFreqData(nid, d, l);
}
FFI_PLUGIN_EXPORT void wajuce_analyser_get_float_time(int32_t nid, float *d,
                                                      int32_t l) {
  auto *e = wajuce::findEngineForNode(nid);
  if (e)
    e->analyserGetFloatTimeData(nid, d, l);
}

FFI_PLUGIN_EXPORT void wajuce_wave_shaper_set_curve(int32_t nid, const float *d,
                                                    int32_t l) {
  auto *e = wajuce::findEngineForNode(nid);
  if (e)
    e->waveShaperSetCurve(nid, d, l);
}
FFI_PLUGIN_EXPORT void wajuce_wave_shaper_set_oversample(int32_t nid,
                                                         int32_t t) {
  auto *e = wajuce::findEngineForNode(nid);
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
  if (type == 0)
    return juce::MidiInput::getAvailableDevices().size();
  return juce::MidiOutput::getAvailableDevices().size();
}

FFI_PLUGIN_EXPORT void wajuce_midi_get_port_name(int32_t type, int32_t index,
                                                 char *buffer,
                                                 int32_t max_len) {
  auto devices = (type == 0) ? juce::MidiInput::getAvailableDevices()
                             : juce::MidiOutput::getAvailableDevices();
  if (index >= 0 && index < devices.size()) {
    juce::String name = devices[index].name;
    name.copyToUTF8(buffer, (size_t)max_len);
  }
}

FFI_PLUGIN_EXPORT void wajuce_midi_port_open(int32_t type, int32_t index) {
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
