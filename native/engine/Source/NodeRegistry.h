#pragma once
/**
 * NodeRegistry.h — Maps integer node IDs to JUCE AudioProcessor instances.
 * Thread-safe with mutex for ID allocation; atomic for parameter access.
 */

#include "ParamAutomation.h"
#include "Processors.h"
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>

namespace wajuce {

enum class NodeType {
  Destination,
  Gain,
  Oscillator,
  BiquadFilter,
  StereoPanner,
  Delay,
  Compressor,
  BufferSource,
  Analyser,
  WaveShaper,
};

struct NodeEntry {
  NodeType type;
  juce::AudioProcessor *processor = nullptr; // owned by AudioProcessorGraph
  std::unique_ptr<juce::AudioProcessor> ownedProcessor; // only if not in graph

  // Convenience typed accessors
  GainProcessor *asGain() { return dynamic_cast<GainProcessor *>(processor); }
  OscillatorProcessor *asOsc() {
    return dynamic_cast<OscillatorProcessor *>(processor);
  }
  BiquadFilterProcessor *asFilter() {
    return dynamic_cast<BiquadFilterProcessor *>(processor);
  }
  StereoPannerProcessor *asPanner() {
    return dynamic_cast<StereoPannerProcessor *>(processor);
  }
  DelayProcessor *asDelay() {
    return dynamic_cast<DelayProcessor *>(processor);
  }
  CompressorProcessor *asCompressor() {
    return dynamic_cast<CompressorProcessor *>(processor);
  }
  BufferSourceProcessor *asBufferSource() {
    return dynamic_cast<BufferSourceProcessor *>(processor);
  }
  AnalyserProcessor *asAnalyser() {
    return dynamic_cast<AnalyserProcessor *>(processor);
  }
  WaveShaperProcessor *asWaveShaper() {
    return dynamic_cast<WaveShaperProcessor *>(processor);
  }

  float getParam(const char *paramName) {
    std::string p(paramName);
    switch (type) {
    case NodeType::Gain:
      if (p == "gain")
        return asGain()->gain;
      break;
    case NodeType::Oscillator:
      if (p == "frequency")
        return asOsc()->frequency;
      else if (p == "detune")
        return asOsc()->detune;
      break;
    case NodeType::BiquadFilter:
      if (p == "frequency")
        return asFilter()->frequency;
      else if (p == "Q")
        return asFilter()->Q;
      else if (p == "gain")
        return asFilter()->gain;
      break;
    case NodeType::Delay:
      if (p == "delayTime")
        return asDelay()->delayTime;
      break;
    case NodeType::Compressor:
      if (p == "threshold")
        return asCompressor()->threshold;
      else if (p == "knee")
        return asCompressor()->knee;
      else if (p == "ratio")
        return asCompressor()->ratio;
      else if (p == "attack")
        return asCompressor()->attack;
      else if (p == "release")
        return asCompressor()->release;
      break;
    case NodeType::BufferSource:
      if (p == "playbackRate")
        return asBufferSource()->playbackRate;
      else if (p == "detune")
        return asBufferSource()->detune;
      else if (p == "decay")
        return asBufferSource()->decay;
      break;
    default:
      break;
    }
    return 0.0f;
  }

  // Automation timelines per param name for this specific node
  std::unordered_map<std::string, std::unique_ptr<ParamTimeline>> timelines;

  ParamTimeline *getOrCreateTimeline(const char *paramName) {
    std::string p(paramName);
    auto it = timelines.find(p);
    if (it == timelines.end()) {
      auto tl = std::make_unique<ParamTimeline>();
      tl->setLastValue(getParam(paramName));
      timelines[p] = std::move(tl);
      return timelines[p].get();
    }
    return it->second.get();
  }
};

class NodeRegistry {
public:
  int32_t add(NodeType type, juce::AudioProcessor *proc) {
    std::lock_guard<std::recursive_mutex> lock(mtx);
    int32_t id = nextId++;
    NodeEntry entry;
    entry.type = type;
    entry.processor = proc;
    nodes[id] = std::move(entry);
    return id;
  }

  NodeEntry *get(int32_t id) {
    std::lock_guard<std::recursive_mutex> lock(mtx);
    auto it = nodes.find(id);
    return it != nodes.end() ? &it->second : nullptr;
  }

  void remove(int32_t id) {
    std::lock_guard<std::recursive_mutex> lock(mtx);
    nodes.erase(id);
  }

  // Get all nodes for the automation loop
  std::unordered_map<int32_t, NodeEntry> &getNodes() { return nodes; }
  std::recursive_mutex &getMutex() { return mtx; }

private:
  std::unordered_map<int32_t, NodeEntry> nodes;
  std::recursive_mutex mtx;
  int32_t nextId = 1;
};

} // namespace wajuce
