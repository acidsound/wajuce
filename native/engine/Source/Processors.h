#pragma once
/**
 * Processors.h — Custom JUCE AudioProcessors for Web Audio nodes.
 * Each class implements a specific node type (Oscillator, Gain, Filter, etc.)
 */

#include <juce_audio_basics/juce_audio_basics.h>
#include <juce_audio_processors/juce_audio_processors.h>
#include <juce_dsp/juce_dsp.h>

#include "RingBuffer.h"
#include <algorithm>
#include <atomic>
#include <vector>

namespace wajuce {

// ============================================================================
// OscillatorProcessor — Sine, Square, Sawtooth, Triangle
// ============================================================================
class OscillatorProcessor : public juce::AudioProcessor {
public:
  OscillatorProcessor()
      : AudioProcessor(BusesProperties().withOutput(
            "Output", juce::AudioChannelSet::discreteChannels(32))) {}

  const juce::String getName() const override { return "WAOscillator"; }

  void prepareToPlay(double sr, int bs) override {
    sampleRate = sr;
    phase = 0.0;
  }
  void releaseResources() override {}

  std::vector<float> wavetable;
  std::mutex waveMutex;
  bool waveValid = false;

  void setPeriodicWave(const float *table, int len) {
    std::lock_guard<std::mutex> lock(waveMutex);
    wavetable.resize(len);
    if (len > 0) {
      std::memcpy(wavetable.data(), table, len * sizeof(float));
      waveValid = true;
    } else {
      waveValid = false;
    }
  }

  void processBlock(juce::AudioBuffer<float> &buf,
                    juce::MidiBuffer &) override {
    double baseTime =
        engineTimePtr ? engineTimePtr->load(std::memory_order_relaxed) : 0.0;

    auto *left = buf.getWritePointer(0);
    auto *right = buf.getNumChannels() > 1 ? buf.getWritePointer(1) : nullptr;
    const float freq = frequency.load(std::memory_order_relaxed);
    const float det = detune.load(std::memory_order_relaxed);
    const float actualFreq = freq * std::pow(2.0f, det / 1200.0f);
    const double phaseInc = actualFreq / sampleRate;
    const int t = type.load(std::memory_order_relaxed);
    const double startT = startTime.load(std::memory_order_relaxed);
    const double stopT = stopTime.load(std::memory_order_relaxed);

    // Lock for custom wave if needed (try_lock to avoid audio thread block, or
    // just lock if short) For simplicity in this demo, we'll access
    // atomic/flag. Ideally we swap pointers or use a lock-free queue, but a
    // mutex for a preset change is often 'ok' in non-rt critical creation.
    // However, this is processBlock. We shouldn't lock potentially.
    // We will check waveValid. The vector data race is a risk if
    // setPeriodicWave is called during playback. We'll use a local copy or
    // try_lock.
    std::unique_lock<std::mutex> lock(waveMutex, std::try_to_lock);
    const bool useWavetable = (t == 4 && waveValid && lock.owns_lock());
    const size_t tableSize = wavetable.size();
    const float *tableData = wavetable.data();

    // If type is custom but no wave, output silence or fallback? Web Audio says
    // silence.

    for (int i = 0; i < buf.getNumSamples(); ++i) {
      double currentTime = baseTime + (double)i / sampleRate;

      if (startT < 0 || currentTime < startT || currentTime >= stopT) {
        left[i] = 0.0f;
        if (right)
          right[i] = 0.0f;
        continue;
      }

      float sample = 0.0f;
      switch (t) {
      case 0: // sine
        sample = std::sin(phase * 2.0 * juce::MathConstants<double>::pi);
        break;
      case 1: // square
        sample = phase < 0.5 ? 1.0f : -1.0f;
        break;
      case 2: // sawtooth
        sample = 2.0f * (float)phase - 1.0f;
        break;
      case 3: // triangle
        sample = (float)(4.0 * std::abs(phase - 0.5) - 1.0);
        break;
      case 4: // custom
        if (useWavetable && tableSize > 0) {
          float idx = (float)(phase * tableSize);
          int idx0 = (int)idx % tableSize;
          int idx1 = (idx0 + 1) % tableSize;
          float frac = idx - (int)idx;
          sample = tableData[idx0] + frac * (tableData[idx1] - tableData[idx0]);
        }
        break;
      }
      for (int ch = 0; ch < buf.getNumChannels(); ++ch)
        buf.getWritePointer(ch)[i] = sample;

      phase += phaseInc;
      if (phase >= 1.0)
        phase -= 1.0;
    }
  }

  void start(double when) { startTime = when; }
  void stop(double when) { stopTime = when; }

  double getTailLengthSeconds() const override { return 0; }
  bool acceptsMidi() const override { return false; }
  bool producesMidi() const override { return false; }
  juce::AudioProcessorEditor *createEditor() override { return nullptr; }
  bool hasEditor() const override { return false; }
  int getNumPrograms() override { return 1; }
  int getCurrentProgram() override { return 0; }
  void setCurrentProgram(int) override {}
  const juce::String getProgramName(int) override { return {}; }
  void changeProgramName(int, const juce::String &) override {}
  void getStateInformation(juce::MemoryBlock &) override {}
  void setStateInformation(const void *, int) override {}

  std::atomic<float> frequency{440.0f};
  std::atomic<float> detune{0.0f};
  std::atomic<int> type{2};
  std::atomic<double> startTime{-1.0};
  std::atomic<double> stopTime{1e15};

  double sampleRate = 44100.0;
  std::atomic<double> *engineTimePtr = nullptr;
  double phase = 0.0;
};

// ============================================================================
// GainProcessor — Simple volume control
// ============================================================================
class GainProcessor : public juce::AudioProcessor {
public:
  GainProcessor()
      : AudioProcessor(
            BusesProperties()
                .withInput("Input", juce::AudioChannelSet::discreteChannels(32))
                .withOutput("Output",
                            juce::AudioChannelSet::discreteChannels(32))) {
    sampleAccurateGains.assign(1024, 1.0f);
  }

  const juce::String getName() const override { return "WAGain"; }
  void prepareToPlay(double, int) override {}
  void releaseResources() override {}

  void processBlock(juce::AudioBuffer<float> &buf,
                    juce::MidiBuffer &) override {
    const int numSamples = buf.getNumSamples();
    const int numChannels = buf.getNumChannels();

    if (isAutomated.load(std::memory_order_relaxed)) {
      if (sampleAccurateGains.size() < (size_t)numSamples) {
        sampleAccurateGains.resize(numSamples, gain.load());
      }
      for (int i = 0; i < numSamples; ++i) {
        const float g = sampleAccurateGains[i];
        for (int ch = 0; ch < numChannels; ++ch) {
          buf.getWritePointer(ch)[i] *= g;
        }
      }
    } else {
      const float g = gain.load(std::memory_order_relaxed);
      buf.applyGain(g);
    }
  }

  double getTailLengthSeconds() const override { return 0; }
  bool acceptsMidi() const override { return false; }
  bool producesMidi() const override { return false; }
  juce::AudioProcessorEditor *createEditor() override { return nullptr; }
  bool hasEditor() const override { return false; }
  int getNumPrograms() override { return 1; }
  int getCurrentProgram() override { return 0; }
  void setCurrentProgram(int) override {}
  const juce::String getProgramName(int) override { return {}; }
  void changeProgramName(int, const juce::String &) override {}
  void getStateInformation(juce::MemoryBlock &) override {}
  void setStateInformation(const void *, int) override {}

  std::atomic<float> gain{1.0f};
  std::vector<float> sampleAccurateGains;
  std::atomic<bool> isAutomated{false};
};

// ============================================================================
// BiquadFilterProcessor
// ============================================================================
class BiquadFilterProcessor : public juce::AudioProcessor {
public:
  BiquadFilterProcessor()
      : AudioProcessor(
            BusesProperties()
                .withInput("Input", juce::AudioChannelSet::discreteChannels(32))
                .withOutput("Output",
                            juce::AudioChannelSet::discreteChannels(32))) {}

  const juce::String getName() const override { return "WABiquadFilter"; }

  void prepareToPlay(double sr, int) override {
    sampleRate = sr;
    smoothedFrequency = juce::jlimit(
        10.0f, (float)(sampleRate * 0.45),
        frequency.load(std::memory_order_relaxed));
    smoothedQ = juce::jmax(0.0001f, Q.load(std::memory_order_relaxed));
    updateCoefficients(smoothedFrequency, smoothedQ);
    for (auto &f : filters)
      f.reset();
  }
  void releaseResources() override {}

  void processBlock(juce::AudioBuffer<float> &buf,
                    juce::MidiBuffer &) override {
    const float targetFreq = juce::jlimit(
        10.0f, (float)(sampleRate * 0.45),
        frequency.load(std::memory_order_relaxed));
    const float targetQ = juce::jmax(0.0001f, Q.load(std::memory_order_relaxed));

    // Smooth coefficient updates across blocks to reduce zipper/tick artifacts.
    constexpr float smoothing = 0.2f;
    smoothedFrequency += (targetFreq - smoothedFrequency) * smoothing;
    smoothedQ += (targetQ - smoothedQ) * smoothing;

    updateCoefficients(smoothedFrequency, smoothedQ);
    for (int ch = 0; ch < buf.getNumChannels(); ++ch) {
      float *data = buf.getWritePointer(ch);
      for (int i = 0; i < buf.getNumSamples(); ++i) {
        data[i] = filters[ch].processSingleSampleRaw(data[i]);
      }
    }
  }

  void updateCoefficients(float freq, float q) {
    juce::IIRCoefficients c =
        juce::IIRCoefficients::makeLowPass(sampleRate, freq, q);
    int t = filterType.load();
    if (t == 1)
      c = juce::IIRCoefficients::makeHighPass(sampleRate, freq, q);
    else if (t == 2)
      c = juce::IIRCoefficients::makeBandPass(sampleRate, freq, q);

    for (auto &f : filters)
      f.setCoefficients(c);
  }

  double getTailLengthSeconds() const override { return 0; }
  bool acceptsMidi() const override { return false; }
  bool producesMidi() const override { return false; }
  juce::AudioProcessorEditor *createEditor() override { return nullptr; }
  bool hasEditor() const override { return false; }
  int getNumPrograms() override { return 1; }
  int getCurrentProgram() override { return 0; }
  void setCurrentProgram(int) override {}
  const juce::String getProgramName(int) override { return {}; }
  void changeProgramName(int, const juce::String &) override {}
  void getStateInformation(juce::MemoryBlock &) override {}
  void setStateInformation(const void *, int) override {}

  std::atomic<float> frequency{350.0f};
  std::atomic<float> Q{1.0f};
  std::atomic<float> gain{0.0f};
  std::atomic<int> filterType{0};
  double sampleRate = 44100.0;
  float smoothedFrequency = 350.0f;
  float smoothedQ = 1.0f;
  juce::IIRFilter filters[32];
};

// ============================================================================
// StereoPannerProcessor
// ============================================================================
class StereoPannerProcessor : public juce::AudioProcessor {
public:
  StereoPannerProcessor()
      : AudioProcessor(
            BusesProperties()
                .withInput("Input", juce::AudioChannelSet::discreteChannels(32))
                .withOutput("Output",
                            juce::AudioChannelSet::discreteChannels(32))) {}

  const juce::String getName() const override { return "WAStereoPanner"; }
  void prepareToPlay(double, int) override {
    lastPan = juce::jlimit(-1.0f, 1.0f, pan.load(std::memory_order_relaxed));
  }
  void releaseResources() override {}

  void processBlock(juce::AudioBuffer<float> &buf,
                    juce::MidiBuffer &) override {
    if (buf.getNumChannels() >= 2 && buf.getNumSamples() > 0) {
      const float targetPan = juce::jlimit(
          -1.0f, 1.0f, pan.load(std::memory_order_relaxed));
      const float panStep =
          (targetPan - lastPan) / (float)buf.getNumSamples();
      float currentPan = lastPan;

      float *left = buf.getWritePointer(0);
      float *right = buf.getWritePointer(1);
      for (int i = 0; i < buf.getNumSamples(); ++i) {
        const float leftGain = std::cos(
            (currentPan + 1.0f) * juce::MathConstants<float>::pi / 4.0f);
        const float rightGain = std::sin(
            (currentPan + 1.0f) * juce::MathConstants<float>::pi / 4.0f);
        left[i] *= leftGain;
        right[i] *= rightGain;
        currentPan += panStep;
      }
      lastPan = targetPan;
    }
  }

  double getTailLengthSeconds() const override { return 0; }
  bool acceptsMidi() const override { return false; }
  bool producesMidi() const override { return false; }
  juce::AudioProcessorEditor *createEditor() override { return nullptr; }
  bool hasEditor() const override { return false; }
  int getNumPrograms() override { return 1; }
  int getCurrentProgram() override { return 0; }
  void setCurrentProgram(int) override {}
  const juce::String getProgramName(int) override { return {}; }
  void changeProgramName(int, const juce::String &) override {}
  void getStateInformation(juce::MemoryBlock &) override {}
  void setStateInformation(const void *, int) override {}

  std::atomic<float> pan{0.0f};
  float lastPan{0.0f};
};

// ============================================================================
// BufferSourceProcessor
// ============================================================================
class BufferSourceProcessor : public juce::AudioProcessor {
public:
  BufferSourceProcessor()
      : AudioProcessor(BusesProperties().withOutput(
            "Output", juce::AudioChannelSet::discreteChannels(32))) {}

  const juce::String getName() const override { return "WABufferSource"; }
  void prepareToPlay(double sr, int) override { sampleRate = sr; }
  void releaseResources() override {}

  void processBlock(juce::AudioBuffer<float> &buf,
                    juce::MidiBuffer &) override {
    const double baseTime =
        engineTimePtr ? engineTimePtr->load(std::memory_order_relaxed) : 0.0;
    const double startT = startTime.load(std::memory_order_relaxed);
    const double stopT = stopTime.load(std::memory_order_relaxed);

    if (!running.load(std::memory_order_relaxed) || bufferData.empty()) {
      buf.clear();
      return;
    }

    const int bufFrames = bufferFrames;
    const float det = detune.load(std::memory_order_relaxed);
    const float rate = std::pow(2.0f, det / 1200.0f) * playbackRate.load();
    const float dec = decay.load(std::memory_order_relaxed);
    const float decayCoeff = std::exp(-1.0f / (dec * (float)sampleRate));
    const int outCh = buf.getNumChannels();

    for (int i = 0; i < buf.getNumSamples(); ++i) {
      double currentTime = baseTime + (double)i / sampleRate;
      if (startT >= 0 && currentTime < startT) {
        for (int ch = 0; ch < outCh; ++ch)
          buf.getWritePointer(ch)[i] = 0.0f;
        continue;
      }
      if (currentTime >= stopT) {
        running = false;
        for (int ch = 0; ch < outCh; ++ch)
          buf.getWritePointer(ch)[i] = 0.0f;
        continue;
      }

      double pos = readPos.load(std::memory_order_relaxed);
      if (pos >= (double)(bufFrames - 1)) {
        if (looping.load(std::memory_order_relaxed)) {
          pos = 0;
          readPos.store(pos, std::memory_order_relaxed);
        } else {
          buf.clear(i, buf.getNumSamples() - i);
          running.store(false, std::memory_order_relaxed);
          return;
        }
      }

      int idx0 = (int)pos;
      int idx1 = idx0 + 1;
      float frac = (float)(pos - idx0);
      float env = currentEnvelope;

      if (bufferChannels == 1) {
        float s0 = bufferData[idx0];
        float s1 = bufferData[idx1];
        float sample = (s0 + frac * (s1 - s0)) * env;
        for (int ch = 0; ch < outCh; ++ch)
          buf.getWritePointer(ch)[i] = sample;
      } else {
        const int numCh = std::min(outCh, bufferChannels);
        for (int ch = 0; ch < numCh; ++ch) {
          float s0 = bufferData[ch * bufFrames + idx0];
          float s1 = bufferData[ch * bufFrames + idx1];
          float sample = (s0 + frac * (s1 - s0)) * env;
          buf.getWritePointer(ch)[i] = sample;
        }
        for (int ch = numCh; ch < outCh; ++ch)
          buf.getWritePointer(ch)[i] = 0.0f;
      }

      currentEnvelope *= decayCoeff;
      readPos.store(pos + rate, std::memory_order_relaxed);
    }
  }

  void setBuffer(const float *data, int frames, int channels, int sr) {
    bufferData.resize(frames * channels);
    std::memcpy(bufferData.data(), data, frames * channels * sizeof(float));
    bufferFrames = frames;
    bufferChannels = channels;
    bufferSampleRate = sr;
    readPos = 0;
  }

  void start(double when) {
    startTime = when;
    readPos = 0;
    currentEnvelope = 1.0f;
    running = true;
  }
  void stop(double when) { stopTime = when; }
  void setLoop(bool loop) { looping = loop; }

  double getTailLengthSeconds() const override { return 0; }
  bool acceptsMidi() const override { return false; }
  bool producesMidi() const override { return false; }
  juce::AudioProcessorEditor *createEditor() override { return nullptr; }
  bool hasEditor() const override { return false; }
  int getNumPrograms() override { return 1; }
  int getCurrentProgram() override { return 0; }
  void setCurrentProgram(int) override {}
  const juce::String getProgramName(int) override { return {}; }
  void changeProgramName(int, const juce::String &) override {}
  void getStateInformation(juce::MemoryBlock &) override {}
  void setStateInformation(const void *, int) override {}

  std::atomic<float> playbackRate{1.0f};
  std::atomic<float> detune{0.0f};
  std::atomic<float> decay{0.5f};
  std::atomic<bool> running{false};
  std::atomic<bool> looping{false};
  std::atomic<double> readPos{0};
  std::atomic<double> startTime{-1.0};
  std::atomic<double> stopTime{1e15};
  std::atomic<double> *engineTimePtr = nullptr;
  float currentEnvelope = 1.0f;
  std::vector<float> bufferData;
  int bufferFrames = 0, bufferChannels = 0, bufferSampleRate = 44100;
  double sampleRate = 44100.0;
};

// ============================================================================
// AnalyserProcessor
// ============================================================================
class AnalyserProcessor : public juce::AudioProcessor {
public:
  AnalyserProcessor()
      : AudioProcessor(
            BusesProperties()
                .withInput("Input", juce::AudioChannelSet::discreteChannels(32))
                .withOutput("Output",
                            juce::AudioChannelSet::discreteChannels(32))) {
    setFftSize(2048);
  }
  const juce::String getName() const override { return "WAAnalyser"; }
  void prepareToPlay(double, int) override {}
  void releaseResources() override {}
  void processBlock(juce::AudioBuffer<float> &buf,
                    juce::MidiBuffer &) override {
    if (buf.getNumChannels() > 0) {
      const float *data = buf.getReadPointer(0);
      for (int i = 0; i < buf.getNumSamples(); ++i) {
        fifo[fifoIndex++] = data[i];
        if (fifoIndex >= fftSize) {
          std::memcpy(fftData.data(), fifo.data(), fftSize * sizeof(float));
          if (forwardFFT)
            forwardFFT->performFrequencyOnlyForwardTransform(fftData.data());
          fifoIndex = 0;
        }
      }
    }
  }
  void setFftSize(int size) {
    fftSize = size;
    forwardFFT = std::make_unique<juce::dsp::FFT>(std::log2(size));
    fftData.assign(size * 2, 0.0f);
    fifo.assign(size, 0.0f);
    fifoIndex = 0;
  }
  void getByteFrequencyData(uint8_t *data, int len) {
    int count = std::min(len, fftSize / 2);
    for (int i = 0; i < count; ++i) {
      float dB = juce::Decibels::gainToDecibels(fftData[i]);
      data[i] = (uint8_t)juce::jlimit(0, 255, (int)((dB + 100.0f) * 2.55f));
    }
  }
  void getByteTimeDomainData(uint8_t *data, int len) {
    int count = std::min(len, fftSize);
    for (int i = 0; i < count; ++i)
      data[i] = (uint8_t)juce::jlimit(0, 255, (int)((fifo[i] + 1.0f) * 127.5f));
  }
  void getFloatFrequencyData(float *data, int len) {
    int count = std::min(len, fftSize / 2);
    for (int i = 0; i < count; ++i)
      data[i] = fftData[i];
  }
  void getFloatTimeDomainData(float *data, int len) {
    int count = std::min(len, fftSize);
    for (int i = 0; i < count; ++i)
      data[i] = fifo[i];
  }

  double getTailLengthSeconds() const override { return 0; }
  bool acceptsMidi() const override { return false; }
  bool producesMidi() const override { return false; }
  juce::AudioProcessorEditor *createEditor() override { return nullptr; }
  bool hasEditor() const override { return false; }
  int getNumPrograms() override { return 1; }
  int getCurrentProgram() override { return 0; }
  void setCurrentProgram(int) override {}
  const juce::String getProgramName(int) override { return {}; }
  void changeProgramName(int, const juce::String &) override {}
  void getStateInformation(juce::MemoryBlock &) override {}
  void setStateInformation(const void *, int) override {}

  int fftSize = 2048;
  std::unique_ptr<juce::dsp::FFT> forwardFFT;
  std::vector<float> fftData, fifo;
  int fifoIndex = 0;
};

// ============================================================================
// CompressorProcessor
// ============================================================================
class CompressorProcessor : public juce::AudioProcessor {
public:
  CompressorProcessor()
      : AudioProcessor(
            BusesProperties()
                .withInput("Input", juce::AudioChannelSet::discreteChannels(32))
                .withOutput("Output",
                            juce::AudioChannelSet::discreteChannels(32))) {}
  const juce::String getName() const override { return "WACompressor"; }
  void prepareToPlay(double sr, int bs) override {
    juce::dsp::ProcessSpec spec{sr, (uint32_t)bs, 32};
    compressor.prepare(spec);
  }
  void releaseResources() override {}
  void processBlock(juce::AudioBuffer<float> &buf,
                    juce::MidiBuffer &) override {
    compressor.setThreshold(threshold.load());
    compressor.setRatio(ratio.load());
    compressor.setAttack(attack.load());
    compressor.setRelease(release.load());
    juce::dsp::AudioBlock<float> block(buf);
    juce::dsp::ProcessContextReplacing<float> context(block);
    compressor.process(context);
  }
  double getTailLengthSeconds() const override { return 0; }
  bool acceptsMidi() const override { return false; }
  bool producesMidi() const override { return false; }
  juce::AudioProcessorEditor *createEditor() override { return nullptr; }
  bool hasEditor() const override { return false; }
  int getNumPrograms() override { return 1; }
  int getCurrentProgram() override { return 0; }
  void setCurrentProgram(int) override {}
  const juce::String getProgramName(int) override { return {}; }
  void changeProgramName(int, const juce::String &) override {}
  void getStateInformation(juce::MemoryBlock &) override {}
  void setStateInformation(const void *, int) override {}

  std::atomic<float> threshold{-20.0f}, ratio{4.0f}, attack{5.0f},
      release{50.0f}, knee{0.0f};
  juce::dsp::Compressor<float> compressor;
};

// ============================================================================
// DelayProcessor
// ============================================================================
class DelayProcessor : public juce::AudioProcessor {
public:
  DelayProcessor(float maxDelay = 2.0f)
      : AudioProcessor(
            BusesProperties()
                .withInput("Input", juce::AudioChannelSet::discreteChannels(32))
                .withOutput("Output",
                            juce::AudioChannelSet::discreteChannels(32))) {
    buffer.setSize(32, (int)(48000 * maxDelay) + 1024);
    buffer.clear();
  }

  const juce::String getName() const override { return "WADelay"; }
  void prepareToPlay(double sr, int) override {
    sampleRate = sr;
    buffer.clear();
    writePos = 0;
  }
  void releaseResources() override {}

  /**
   * ARCHITECTURAL NOTE: Sample-Accurate Fractional Delay
   * 1. Fractional Delay: delayTime is NOT rounded to integers to avoid clicks.
   * 2. Linear Interpolation: Output is weighted average of two adjacent
   * samples.
   * 3. Sample-Accurate Buffer: Engine pre-fills sampleAccurateDelayTimes
   *    (avoiding circular header dependency with NodeRegistry).
   */
  void processBlock(juce::AudioBuffer<float> &buf,
                    juce::MidiBuffer &) override {
    const int bufLen = buffer.getNumSamples();
    const int numChannels = buf.getNumChannels();
    const int numSamples = buf.getNumSamples();
    const bool automated = isAutomated.load(std::memory_order_relaxed);

    // Resize if provided buffer is smaller than current processing block
    if (sampleAccurateDelayTimes.size() < (size_t)numSamples) {
      sampleAccurateDelayTimes.resize(numSamples, delayTime.load());
    }

    for (int ch = 0; ch < numChannels; ++ch) {
      float *delayData = buffer.getWritePointer(ch);
      float *bufData = buf.getWritePointer(ch);
      int wPos = writePos;

      for (int i = 0; i < numSamples; ++i) {
        const float currentDelaySeconds =
            automated ? sampleAccurateDelayTimes[i]
                      : delayTime.load(std::memory_order_relaxed);
        const float currentDelaySamples =
            currentDelaySeconds * (float)sampleRate;

        // 1. Fractional Read Position
        float rp = (float)wPos - currentDelaySamples;
        while (rp < 0)
          rp += (float)bufLen;

        int i1 = (int)rp;
        int i2 = (i1 + 1) % bufLen;
        float frac = rp - (float)i1;

        // 2. Linear Interpolation
        float out = delayData[i1] + frac * (delayData[i2] - delayData[i1]);

        // 3. Write to delay buffer with feedback.
        // DelayNode in Web Audio is usually used with an external feedback loop,
        // but wajuce also exposes an experimental internal feedback param.
        float inSample = bufData[i];
        float fb =
            juce::jlimit(0.0f, 0.9995f, feedback.load(std::memory_order_relaxed));
        delayData[wPos] = inSample + out * fb;

        // 4. Output mix
        bufData[i] = out; // Simple 100% wet for now to match other nodes
        // (Actually Web Audio DelayNode is 100% wet, mix happens via
        // connections)

        wPos = (wPos + 1) % bufLen;
      }
    }

    writePos = (writePos + numSamples) % bufLen;
  }
  double getTailLengthSeconds() const override { return 0; }
  bool acceptsMidi() const override { return false; }
  bool producesMidi() const override { return false; }
  juce::AudioProcessorEditor *createEditor() override { return nullptr; }
  bool hasEditor() const override { return false; }
  int getNumPrograms() override { return 1; }
  int getCurrentProgram() override { return 0; }
  void setCurrentProgram(int) override {}
  const juce::String getProgramName(int) override { return {}; }
  void changeProgramName(int, const juce::String &) override {}
  void getStateInformation(juce::MemoryBlock &) override {}
  void setStateInformation(const void *, int) override {}

  std::atomic<float> delayTime{0.3f};
  std::atomic<float> feedback{0.0f};
  std::atomic<bool> isAutomated{false};
  double sampleRate = 44100.0;
  juce::AudioBuffer<float> buffer;
  int writePos = 0;

  std::vector<float> sampleAccurateDelayTimes;
};

// ============================================================================
// WaveShaperProcessor
// ============================================================================
class WaveShaperProcessor : public juce::AudioProcessor {
public:
  WaveShaperProcessor()
      : AudioProcessor(
            BusesProperties()
                .withInput("Input", juce::AudioChannelSet::discreteChannels(32))
                .withOutput("Output",
                            juce::AudioChannelSet::discreteChannels(32))) {
    curve.assign(1024, 0.0f);
    for (int i = 0; i < 1024; ++i)
      curve[i] = std::tanh((float)i / 512.0f - 1.0f);
  }
  const juce::String getName() const override { return "WAWaveShaper"; }
  void prepareToPlay(double, int) override {}
  void releaseResources() override {}
  void processBlock(juce::AudioBuffer<float> &buf,
                    juce::MidiBuffer &) override {
    for (int ch = 0; ch < buf.getNumChannels(); ++ch) {
      float *data = buf.getWritePointer(ch);
      for (int i = 0; i < buf.getNumSamples(); ++i) {
        float idx = (data[i] + 1.0f) * 511.5f;
        data[i] = curve[juce::jlimit(0, 1023, (int)idx)];
      }
    }
  }
  void setCurve(const float *d, int l) { curve.assign(d, d + l); }
  void setOversample(int) {}
  double getTailLengthSeconds() const override { return 0; }
  bool acceptsMidi() const override { return false; }
  bool producesMidi() const override { return false; }
  juce::AudioProcessorEditor *createEditor() override { return nullptr; }
  bool hasEditor() const override { return false; }
  int getNumPrograms() override { return 1; }
  int getCurrentProgram() override { return 0; }
  void setCurrentProgram(int) override {}
  const juce::String getProgramName(int) override { return {}; }
  void changeProgramName(int, const juce::String &) override {}
  void getStateInformation(juce::MemoryBlock &) override {}
  void setStateInformation(const void *, int) override {}

  std::vector<float> curve;
};

// ============================================================================
// Feedback Bridge (For Cycle Support)
// ============================================================================
class FeedbackSenderProcessor : public juce::AudioProcessor {
public:
  FeedbackSenderProcessor(std::shared_ptr<juce::AudioBuffer<float>> sharedBuf)
      : AudioProcessor(BusesProperties().withInput(
            "Input", juce::AudioChannelSet::discreteChannels(32))),
        buffer(sharedBuf) {}

  const juce::String getName() const override { return "WAFeedbackSender"; }
  void prepareToPlay(double, int samples) override {
    if (buffer && buffer->getNumSamples() < samples) {
      buffer->setSize(2, samples);
    }
  }
  void releaseResources() override {}
  void processBlock(juce::AudioBuffer<float> &buf,
                    juce::MidiBuffer &) override {
    if (buffer) {
      for (int ch = 0;
           ch < std::min(buf.getNumChannels(), buffer->getNumChannels());
           ++ch) {
        buffer->copyFrom(ch, 0, buf, ch, 0, buf.getNumSamples());
      }
    }
  }

  double getTailLengthSeconds() const override { return 0; }
  bool acceptsMidi() const override { return false; }
  bool producesMidi() const override { return false; }
  juce::AudioProcessorEditor *createEditor() override { return nullptr; }
  bool hasEditor() const override { return false; }
  int getNumPrograms() override { return 1; }
  int getCurrentProgram() override { return 0; }
  void setCurrentProgram(int) override {}
  const juce::String getProgramName(int) override { return {}; }
  void changeProgramName(int, const juce::String &) override {}
  void getStateInformation(juce::MemoryBlock &) override {}
  void setStateInformation(const void *, int) override {}

private:
  std::shared_ptr<juce::AudioBuffer<float>> buffer;
};

class FeedbackReceiverProcessor : public juce::AudioProcessor {
public:
  FeedbackReceiverProcessor(std::shared_ptr<juce::AudioBuffer<float>> sharedBuf)
      : AudioProcessor(BusesProperties().withOutput(
            "Output", juce::AudioChannelSet::discreteChannels(32))),
        buffer(sharedBuf) {}

  const juce::String getName() const override { return "WAFeedbackReceiver"; }
  void prepareToPlay(double, int samples) override {
    if (buffer && buffer->getNumSamples() < samples) {
      buffer->setSize(2, samples);
    }
  }
  void releaseResources() override {}
  void processBlock(juce::AudioBuffer<float> &buf,
                    juce::MidiBuffer &) override {
    buf.clear();
    if (buffer) {
      for (int ch = 0;
           ch < std::min(buf.getNumChannels(), buffer->getNumChannels());
           ++ch) {
        buf.copyFrom(ch, 0, *buffer, ch, 0, buf.getNumSamples());
      }
    }
  }

  double getTailLengthSeconds() const override { return 0; }
  bool acceptsMidi() const override { return false; }
  bool producesMidi() const override { return false; }
  juce::AudioProcessorEditor *createEditor() override { return nullptr; }
  bool hasEditor() const override { return false; }
  int getNumPrograms() override { return 1; }
  int getCurrentProgram() override { return 0; }
  void setCurrentProgram(int) override {}
  const juce::String getProgramName(int) override { return {}; }
  void changeProgramName(int, const juce::String &) override {}
  void getStateInformation(juce::MemoryBlock &) override {}
  void setStateInformation(const void *, int) override {}

private:
  std::shared_ptr<juce::AudioBuffer<float>> buffer;
};

// ============================================================================
// MediaStreamSourceProcessor — Proxy for physical input
// ============================================================================
class MediaStreamSourceProcessor : public juce::AudioProcessor {
public:
  MediaStreamSourceProcessor()
      : AudioProcessor(
            BusesProperties()
                .withInput("Input", juce::AudioChannelSet::discreteChannels(32))
                .withOutput("Output",
                            juce::AudioChannelSet::discreteChannels(32))) {}
  const juce::String getName() const override { return "WAMediaStreamSource"; }
  void prepareToPlay(double, int) override {}
  void releaseResources() override {}
  void processBlock(juce::AudioBuffer<float> &buf,
                    juce::MidiBuffer &) override {
    // If hardware input is mono (common on iOS), duplicate ch0 into ch1
    // so monitoring path is centered on stereo outputs.
    if (buf.getNumChannels() < 2 || buf.getNumSamples() <= 0)
      return;

    const float *left = buf.getReadPointer(0);
    const float *rightIn = buf.getReadPointer(1);

    bool rightHasSignal = false;
    for (int i = 0; i < buf.getNumSamples(); ++i) {
      if (std::abs(rightIn[i]) > 1.0e-7f) {
        rightHasSignal = true;
        break;
      }
    }

    if (!rightHasSignal) {
      buf.copyFrom(1, 0, left, buf.getNumSamples());
    }
  }
  double getTailLengthSeconds() const override { return 0; }
  bool acceptsMidi() const override { return false; }
  bool producesMidi() const override { return false; }
  juce::AudioProcessorEditor *createEditor() override { return nullptr; }
  bool hasEditor() const override { return false; }
  int getNumPrograms() override { return 1; }
  int getCurrentProgram() override { return 0; }
  void setCurrentProgram(int) override {}
  const juce::String getProgramName(int) override { return {}; }
  void changeProgramName(int, const juce::String &) override {}
  void getStateInformation(juce::MemoryBlock &) override {}
  void setStateInformation(const void *, int) override {}
};

// ============================================================================
// MediaStreamDestinationProcessor — Capture output
// ============================================================================
class MediaStreamDestinationProcessor : public juce::AudioProcessor {
public:
  MediaStreamDestinationProcessor()
      : AudioProcessor(BusesProperties().withInput(
            "Input", juce::AudioChannelSet::discreteChannels(32))) {}
  const juce::String getName() const override {
    return "WAMediaStreamDestination";
  }
  void prepareToPlay(double, int) override {}
  void releaseResources() override {}
  void processBlock(juce::AudioBuffer<float> &buf,
                    juce::MidiBuffer &) override {
    // Basic implementation: could store in a ring buffer for Dart to read
  }
  double getTailLengthSeconds() const override { return 0; }
  bool acceptsMidi() const override { return false; }
  bool producesMidi() const override { return false; }
  juce::AudioProcessorEditor *createEditor() override { return nullptr; }
  bool hasEditor() const override { return false; }
  int getNumPrograms() override { return 1; }
  int getCurrentProgram() override { return 0; }
  void setCurrentProgram(int) override {}
  const juce::String getProgramName(int) override { return {}; }
  void changeProgramName(int, const juce::String &) override {}
  void getStateInformation(juce::MemoryBlock &) override {}
  void setStateInformation(const void *, int) override {}
};

// ============================================================================
// ChannelSplitterProcessor — 1 input (multi-ch) -> many outputs
// ============================================================================
class ChannelSplitterProcessor : public juce::AudioProcessor {
public:
  ChannelSplitterProcessor(int outputs = 6)
      : AudioProcessor(
            BusesProperties()
                .withInput("Input", juce::AudioChannelSet::discreteChannels(32))
                .withOutput("Output",
                            juce::AudioChannelSet::discreteChannels(32))) {}
  const juce::String getName() const override { return "WAChannelSplitter"; }
  void prepareToPlay(double, int) override {}
  void releaseResources() override {}
  void processBlock(juce::AudioBuffer<float> &buf,
                    juce::MidiBuffer &) override {}
  double getTailLengthSeconds() const override { return 0; }
  bool acceptsMidi() const override { return false; }
  bool producesMidi() const override { return false; }
  juce::AudioProcessorEditor *createEditor() override { return nullptr; }
  bool hasEditor() const override { return false; }
  int getNumPrograms() override { return 1; }
  int getCurrentProgram() override { return 0; }
  void setCurrentProgram(int) override {}
  const juce::String getProgramName(int) override { return {}; }
  void changeProgramName(int, const juce::String &) override {}
  void getStateInformation(juce::MemoryBlock &) override {}
  void setStateInformation(const void *, int) override {}
};

// ============================================================================
// ChannelMergerProcessor — many inputs -> 1 output (multi-ch)
// ============================================================================
class ChannelMergerProcessor : public juce::AudioProcessor {
public:
  ChannelMergerProcessor(int inputs = 6)
      : AudioProcessor(
            BusesProperties()
                .withInput("Input", juce::AudioChannelSet::discreteChannels(32))
                .withOutput("Output",
                            juce::AudioChannelSet::discreteChannels(32))) {}
  const juce::String getName() const override { return "WAChannelMerger"; }
  void prepareToPlay(double, int) override {}
  void releaseResources() override {}
  void processBlock(juce::AudioBuffer<float> &buf,
                    juce::MidiBuffer &) override {}
  double getTailLengthSeconds() const override { return 0; }
  bool acceptsMidi() const override { return false; }
  bool producesMidi() const override { return false; }
  juce::AudioProcessorEditor *createEditor() override { return nullptr; }
  bool hasEditor() const override { return false; }
  int getNumPrograms() override { return 1; }
  int getCurrentProgram() override { return 0; }
  void setCurrentProgram(int) override {}
  const juce::String getProgramName(int) override { return {}; }
  void changeProgramName(int, const juce::String &) override {}
  void getStateInformation(juce::MemoryBlock &) override {}
  void setStateInformation(const void *, int) override {}
};

// ============================================================================
// WorkletBridgeProcessor — Bridge between JUCE and Dart Audio Isolate
// ============================================================================
class WorkletBridgeProcessor : public juce::AudioProcessor {
public:
  WorkletBridgeProcessor(int inputs = 2, int outputs = 2)
      : AudioProcessor(
            BusesProperties()
                .withInput("Input", juce::AudioChannelSet::discreteChannels(32))
                .withOutput("Output",
                            juce::AudioChannelSet::discreteChannels(32))),
        numInputs(inputs), numOutputs(outputs) {
    // Initial buffer creation (stereo 4096 capacity by default)
    toIsolate = std::make_unique<MultiChannelSPSCRingBuffer>(inputs, 8192);
    fromIsolate = std::make_unique<MultiChannelSPSCRingBuffer>(outputs, 8192);
  }

  const juce::String getName() const override { return "WAWorkletBridge"; }

  void prepareToPlay(double, int) override {
    toIsolate->clear();
    fromIsolate->clear();
  }

  void releaseResources() override {}

  void processBlock(juce::AudioBuffer<float> &buf,
                    juce::MidiBuffer &) override {
    const int numSamples = buf.getNumSamples();
    const int activeInputs = std::min(buf.getNumChannels(), numInputs);
    const int activeOutputs = std::min(buf.getNumChannels(), numOutputs);

    // 1. Write Input from Engine -> Isolate
    for (int ch = 0; ch < activeInputs; ++ch) {
      if (auto *rb = toIsolate->getChannel(ch)) {
        rb->write(buf.getReadPointer(ch), numSamples);
      }
    }

    // 2. Read Output from Isolate -> Engine
    buf.clear(); // Clear before reading from worklet
    for (int ch = 0; ch < activeOutputs; ++ch) {
      if (auto *rb = fromIsolate->getChannel(ch)) {
        rb->read(buf.getWritePointer(ch), numSamples);
      }
    }
  }

  double getTailLengthSeconds() const override { return 0; }
  bool acceptsMidi() const override { return false; }
  bool producesMidi() const override { return false; }
  juce::AudioProcessorEditor *createEditor() override { return nullptr; }
  bool hasEditor() const override { return false; }
  int getNumPrograms() override { return 1; }
  int getCurrentProgram() override { return 0; }
  void setCurrentProgram(int) override {}
  const juce::String getProgramName(int) override { return {}; }
  void changeProgramName(int, const juce::String &) override {}
  void getStateInformation(juce::MemoryBlock &) override {}
  void setStateInformation(const void *, int) override {}

  int numInputs;
  int numOutputs;
  std::unique_ptr<MultiChannelSPSCRingBuffer> toIsolate;
  std::unique_ptr<MultiChannelSPSCRingBuffer> fromIsolate;
};

} // namespace wajuce
