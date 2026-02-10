#pragma once
/**
 * Processors.h — Custom JUCE AudioProcessors for Web Audio nodes.
 * Each class implements a specific node type (Oscillator, Gain, Filter, etc.)
 */

#include <juce_audio_basics/juce_audio_basics.h>
#include <juce_audio_processors/juce_audio_processors.h>
#include <juce_dsp/juce_dsp.h>

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
            "Output", juce::AudioChannelSet::stereo())) {}

  const juce::String getName() const override { return "WAOscillator"; }

  void prepareToPlay(double sr, int bs) override {
    sampleRate = sr;
    phase = 0.0;
  }
  void releaseResources() override {}

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
      }
      left[i] = sample;
      if (right)
        right[i] = sample;

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
                .withInput("Input", juce::AudioChannelSet::stereo())
                .withOutput("Output", juce::AudioChannelSet::stereo())) {
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
                .withInput("Input", juce::AudioChannelSet::stereo())
                .withOutput("Output", juce::AudioChannelSet::stereo())) {}

  const juce::String getName() const override { return "WABiquadFilter"; }

  void prepareToPlay(double sr, int) override {
    sampleRate = sr;
    updateCoefficients();
    for (auto &f : filters)
      f.reset();
  }
  void releaseResources() override {}

  void processBlock(juce::AudioBuffer<float> &buf,
                    juce::MidiBuffer &) override {
    updateCoefficients();
    for (int ch = 0; ch < buf.getNumChannels() && ch < 2; ++ch) {
      float *data = buf.getWritePointer(ch);
      for (int i = 0; i < buf.getNumSamples(); ++i) {
        data[i] = filters[ch].processSingleSampleRaw(data[i]);
      }
    }
  }

  void updateCoefficients() {
    juce::IIRCoefficients c = juce::IIRCoefficients::makeLowPass(
        sampleRate, frequency.load(), Q.load());
    int t = filterType.load();
    if (t == 1)
      c = juce::IIRCoefficients::makeHighPass(sampleRate, frequency.load(),
                                              Q.load());
    else if (t == 2)
      c = juce::IIRCoefficients::makeBandPass(sampleRate, frequency.load(),
                                              Q.load());

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
  juce::IIRFilter filters[2];
};

// ============================================================================
// StereoPannerProcessor
// ============================================================================
class StereoPannerProcessor : public juce::AudioProcessor {
public:
  StereoPannerProcessor()
      : AudioProcessor(
            BusesProperties()
                .withInput("Input", juce::AudioChannelSet::stereo())
                .withOutput("Output", juce::AudioChannelSet::stereo())) {}

  const juce::String getName() const override { return "WAStereoPanner"; }
  void prepareToPlay(double, int) override {}
  void releaseResources() override {}

  void processBlock(juce::AudioBuffer<float> &buf,
                    juce::MidiBuffer &) override {
    const float p = pan.load(std::memory_order_relaxed);
    const float leftGain =
        std::cos((p + 1.0f) * juce::MathConstants<float>::pi / 4.0f);
    const float rightGain =
        std::sin((p + 1.0f) * juce::MathConstants<float>::pi / 4.0f);
    if (buf.getNumChannels() >= 2) {
      buf.applyGain(0, 0, buf.getNumSamples(), leftGain);
      buf.applyGain(1, 0, buf.getNumSamples(), rightGain);
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
};

// ============================================================================
// BufferSourceProcessor
// ============================================================================
class BufferSourceProcessor : public juce::AudioProcessor {
public:
  BufferSourceProcessor()
      : AudioProcessor(BusesProperties().withOutput(
            "Output", juce::AudioChannelSet::stereo())) {}

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
                .withInput("Input", juce::AudioChannelSet::stereo())
                .withOutput("Output", juce::AudioChannelSet::stereo())) {
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
                .withInput("Input", juce::AudioChannelSet::stereo())
                .withOutput("Output", juce::AudioChannelSet::stereo())) {}
  const juce::String getName() const override { return "WACompressor"; }
  void prepareToPlay(double sr, int bs) override {
    juce::dsp::ProcessSpec spec{sr, (uint32_t)bs, 2};
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
                .withInput("Input", juce::AudioChannelSet::stereo())
                .withOutput("Output", juce::AudioChannelSet::stereo())) {
    buffer.setSize(2, (int)(48000 * maxDelay) + 1024);
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

    // Resize if provided buffer is smaller than current processing block
    if (sampleAccurateDelayTimes.size() < (size_t)numSamples) {
      sampleAccurateDelayTimes.resize(numSamples, delayTime.load());
    }

    float *delayDataL = buffer.getWritePointer(0);
    float *delayDataR =
        numChannels > 1 ? buffer.getWritePointer(1) : delayDataL;

    const float fb = feedback.load(std::memory_order_relaxed);
    const bool automated = isAutomated.load(std::memory_order_relaxed);

    for (int i = 0; i < numSamples; ++i) {
      const float currentDelaySeconds =
          automated ? sampleAccurateDelayTimes[i]
                    : delayTime.load(std::memory_order_relaxed);
      const float currentDelaySamples = currentDelaySeconds * (float)sampleRate;

      // 1. Fractional Read Position
      float rp = (float)writePos - currentDelaySamples;
      while (rp < 0)
        rp += (float)bufLen;

      int i1 = (int)rp;
      int i2 = (i1 + 1) % bufLen;
      float frac = rp - (float)i1;

      for (int ch = 0; ch < numChannels && ch < 2; ++ch) {
        float *delayLine = (ch == 0) ? delayDataL : delayDataR;

        // 2. Linear Interpolation
        float d1 = delayLine[i1];
        float d2 = delayLine[i2];
        float delayed = d1 + frac * (d2 - d1);

        // 3. Store Input + Internal Feedback
        float input = buf.getReadPointer(ch)[i];
        delayLine[writePos] = input + (delayed * fb);

        // 4. Output Wet Signal
        buf.getWritePointer(ch)[i] = delayed;
      }
      writePos = (writePos + 1) % bufLen;
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
                .withInput("Input", juce::AudioChannelSet::stereo())
                .withOutput("Output", juce::AudioChannelSet::stereo())) {
    curve.assign(1024, 0.0f);
    for (int i = 0; i < 1024; ++i)
      curve[i] = std::tanh((float)i / 512.0f - 1.0f);
  }
  const juce::String getName() const override { return "WAWaveShaper"; }
  void prepareToPlay(double, int) override {}
  void releaseResources() override {}
  void processBlock(juce::AudioBuffer<float> &buf,
                    juce::MidiBuffer &) override {
    for (int ch = 0; ch < buf.getNumChannels() && ch < 2; ++ch) {
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
            "Input", juce::AudioChannelSet::stereo())),
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
            "Output", juce::AudioChannelSet::stereo())),
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

} // namespace wajuce
