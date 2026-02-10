/**
 * WajuceEngine.cpp — Implementation of the JUCE audio engine.
 */

#include "WajuceEngine.h"
#include <cassert>
#include <cstdio>
#include <cstring>
#ifdef JUCE_IOS
#import <Foundation/Foundation.h>
#define WA_LOG(fmt, ...) fprintf(stderr, fmt "\n", ##__VA_ARGS__)
#else
#define WA_LOG(fmt, ...) fprintf(stderr, fmt "\n", ##__VA_ARGS__)
#endif

namespace wajuce {

using NodeID = juce::AudioProcessorGraph::NodeID;

// ============================================================================
// Engine Implementation
// ============================================================================

Engine::Engine(double sr, int bs) : sampleRate(sr), bufferSize(bs) {
  WA_LOG("[wajuce] Engine::Engine sr=%f, bs=%d", sr, bs);
  graph = std::make_unique<juce::AudioProcessorGraph>();
  graph->setPlayConfigDetails(2, 2, sampleRate, bufferSize);
  graph->prepareToPlay(sampleRate, bufferSize);

  inputNode = graph->addNode(
      std::make_unique<juce::AudioProcessorGraph::AudioGraphIOProcessor>(
          juce::AudioProcessorGraph::AudioGraphIOProcessor::audioInputNode));
  outputNode = graph->addNode(
      std::make_unique<juce::AudioProcessorGraph::AudioGraphIOProcessor>(
          juce::AudioProcessorGraph::AudioGraphIOProcessor::audioOutputNode));

  auto err = deviceManager.initialiseWithDefaultDevices(0, 2);
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
  graph->setPlayConfigDetails(2, 2, sr, samples);
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
  proxy.clear();
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

  attemptConnect(output, input);

  // Implicitly connect second channel for common stereo scenarios
  if (output == 0 && input == 0) {
    attemptConnect(1, 1);
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
void Engine::oscStop(int32_t nodeId, double when) {
  auto *entry = registry.get(nodeId);
  if (entry && entry->type == NodeType::Oscillator)
    entry->asOsc()->stop(when);
}

void Engine::filterSetType(int32_t nodeId, int type) {
  auto *entry = registry.get(nodeId);
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
#include "../../../src/wajuce.h"
static wajuce::Engine *getEngine(int32_t ctx_id);
FFI_PLUGIN_EXPORT int32_t wajuce_context_create(int32_t sr, int32_t bs) {
  std::lock_guard<std::mutex> lock(wajuce::g_engineMtx);
  auto engine = std::make_unique<wajuce::Engine>((double)sr, bs);
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
FFI_PLUGIN_EXPORT void
wajuce_analyser_get_byte_freq_data(int32_t nid, uint8_t *d, int32_t l) {
  auto *e = wajuce::findEngineForNode(nid);
  if (e)
    e->analyserGetByteFreqData(nid, d, l);
}
FFI_PLUGIN_EXPORT void
wajuce_analyser_get_byte_time_data(int32_t nid, uint8_t *d, int32_t l) {
  auto *e = wajuce::findEngineForNode(nid);
  if (e)
    e->analyserGetByteTimeData(nid, d, l);
}
FFI_PLUGIN_EXPORT void
wajuce_analyser_get_float_freq_data(int32_t nid, float *d, int32_t l) {
  auto *e = wajuce::findEngineForNode(nid);
  if (e)
    e->analyserGetFloatFreqData(nid, d, l);
}
FFI_PLUGIN_EXPORT void
wajuce_analyser_get_float_time_data(int32_t nid, float *d, int32_t l) {
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

static wajuce::Engine *getEngine(int32_t id) {
  auto it = wajuce::g_engines.find(id);
  return it != wajuce::g_engines.end() ? it->second.get() : nullptr;
}

} // extern "C"

namespace wajuce {
std::unordered_map<int32_t, std::unique_ptr<Engine>> g_engines;
std::mutex g_engineMtx;
int32_t g_nextCtxId = 1;

Engine *findEngineForNode(int32_t nodeId) {
  for (auto &[id, engine] : g_engines) {
    if (engine->getRegistry().get(nodeId))
      return engine.get();
  }
  return nullptr;
}
} // namespace wajuce
