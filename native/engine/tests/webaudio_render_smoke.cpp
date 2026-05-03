#include "../../../src/wajuce.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>

namespace {

bool expect(bool condition, const char *message) {
  if (!condition) {
    std::fprintf(stderr, "FAIL: %s\n", message);
    return false;
  }
  return true;
}

double rms(const std::vector<float> &buffer, int frames, int channel) {
  double sum = 0.0;
  const int offset = channel * frames;
  for (int i = 0; i < frames; ++i) {
    const double v = buffer[static_cast<size_t>(offset + i)];
    sum += v * v;
  }
  return std::sqrt(sum / frames);
}

int peakIndex(const std::vector<float> &buffer, int frames, int channel) {
  int peak = 0;
  float peakAbs = 0.0f;
  const int offset = channel * frames;
  for (int i = 0; i < frames; ++i) {
    const float value = std::abs(buffer[static_cast<size_t>(offset + i)]);
    if (value > peakAbs) {
      peakAbs = value;
      peak = i;
    }
  }
  return peak;
}

bool near(float actual, float expected, float tolerance) {
  return std::abs(actual - expected) <= tolerance;
}

void putLE16(std::vector<uint8_t> &data, uint16_t value) {
  data.push_back(static_cast<uint8_t>(value & 0xFF));
  data.push_back(static_cast<uint8_t>((value >> 8) & 0xFF));
}

void putLE32(std::vector<uint8_t> &data, uint32_t value) {
  data.push_back(static_cast<uint8_t>(value & 0xFF));
  data.push_back(static_cast<uint8_t>((value >> 8) & 0xFF));
  data.push_back(static_cast<uint8_t>((value >> 16) & 0xFF));
  data.push_back(static_cast<uint8_t>((value >> 24) & 0xFF));
}

void putLE64(std::vector<uint8_t> &data, uint64_t value) {
  for (int i = 0; i < 8; ++i) {
    data.push_back(static_cast<uint8_t>((value >> (8 * i)) & 0xFF));
  }
}

void putBE16(std::vector<uint8_t> &data, uint16_t value) {
  data.push_back(static_cast<uint8_t>((value >> 8) & 0xFF));
  data.push_back(static_cast<uint8_t>(value & 0xFF));
}

void putBE32(std::vector<uint8_t> &data, uint32_t value) {
  data.push_back(static_cast<uint8_t>((value >> 24) & 0xFF));
  data.push_back(static_cast<uint8_t>((value >> 16) & 0xFF));
  data.push_back(static_cast<uint8_t>((value >> 8) & 0xFF));
  data.push_back(static_cast<uint8_t>(value & 0xFF));
}

void putLEFloat64(std::vector<uint8_t> &data, double value) {
  uint64_t raw = 0;
  std::memcpy(&raw, &value, sizeof(double));
  putLE64(data, raw);
}

void putBEFloat32(std::vector<uint8_t> &data, float value) {
  uint32_t raw = 0;
  std::memcpy(&raw, &value, sizeof(float));
  putBE32(data, raw);
}

void putTag(std::vector<uint8_t> &data, const char *tag) {
  data.insert(data.end(), tag, tag + 4);
}

} // namespace

int main() {
  bool ok = true;

  {
    constexpr int sampleRate = 44100;
    constexpr int frames = 44100;
    constexpr int channels = 2;
    const int ctx = wajuce_context_create(sampleRate, 128, 0, channels);
    const int osc = wajuce_create_oscillator(ctx);
    const int gain = wajuce_create_gain(ctx);
    const int dest = wajuce_context_get_destination_id(ctx);
    wajuce_param_set(osc, "frequency", 440.0f);
    wajuce_param_set(gain, "gain", 0.25f);
    wajuce_connect(ctx, osc, gain, 0, 0);
    wajuce_connect(ctx, gain, dest, 0, 0);
    wajuce_osc_start(osc, 0.0);

    std::vector<float> out(static_cast<size_t>(frames * channels), 0.0f);
    wajuce_context_render(ctx, out.data(), frames, channels);
    const double left = rms(out, frames, 0);
    const double right = rms(out, frames, 1);
    ok &= expect(left > 0.15 && left < 0.20,
                 "oscillator/gain left RMS should match a 0.25 sine");
    ok &= expect(std::abs(left - right) < 0.001,
                 "oscillator output should be stereo-balanced");
    wajuce_context_destroy(ctx);
  }

  {
    constexpr int sampleRate = 100;
    constexpr int frames = 16;
    constexpr int channels = 1;
    const int ctx = wajuce_context_create(sampleRate, 16, 0, channels);
    const int carrier = wajuce_create_constant_source(ctx);
    const int mod = wajuce_create_constant_source(ctx);
    const int gain = wajuce_create_gain(ctx);
    const int dest = wajuce_context_get_destination_id(ctx);
    wajuce_param_set(carrier, "offset", 1.0f);
    wajuce_param_set(mod, "offset", 0.25f);
    wajuce_param_set(gain, "gain", 0.0f);
    wajuce_connect(ctx, carrier, gain, 0, 0);
    wajuce_connect_param(ctx, mod, gain, "gain", 0);
    wajuce_connect(ctx, gain, dest, 0, 0);
    wajuce_osc_start(carrier, 0.0);
    wajuce_osc_start(mod, 0.0);
    std::vector<float> out(static_cast<size_t>(frames * channels), 0.0f);
    wajuce_context_render(ctx, out.data(), frames, channels);
    ok &= expect(near(out[0], 0.25f, 0.001f) &&
                     near(out[frames - 1], 0.25f, 0.001f),
                 "AudioNode.connect(AudioParam) should modulate gain");
    wajuce_disconnect_param(ctx, mod, gain, "gain", 0);
    std::fill(out.begin(), out.end(), 0.0f);
    wajuce_context_render(ctx, out.data(), frames, channels);
    ok &= expect(rms(out, frames, 0) < 0.0001,
                 "AudioNode.disconnect(AudioParam) should remove modulation");
    wajuce_context_destroy(ctx);
  }

  {
    constexpr int sampleRate = 44100;
    constexpr int frames = 512;
    constexpr int channels = 2;
    const int ctx = wajuce_context_create(sampleRate, 128, 0, channels);
    int32_t ids[7] = {0};
    wajuce_create_machine_voice(ctx, ids);
    const int dest = wajuce_context_get_destination_id(ctx);
    wajuce_param_set(ids[2], "gain", 0.5f);
    wajuce_connect(ctx, ids[3], dest, 0, 0);
    wajuce_connect(ctx, ids[6], dest, 0, 0);
    std::vector<float> out(static_cast<size_t>(frames * channels), 0.0f);
    wajuce_context_render(ctx, out.data(), frames, channels);
    ok &= expect(rms(out, frames, 0) < 0.0001,
                 "inactive MachineVoice spares should not render");
    std::fill(out.begin(), out.end(), 0.0f);
    wajuce_machine_voice_set_active(ctx, ids[0], 1);
    wajuce_context_render(ctx, out.data(), frames, channels);
    ok &= expect(rms(out, frames, 0) > 0.01,
                 "active MachineVoice should render after activation");
    wajuce_context_destroy(ctx);
  }

  {
    constexpr int sampleRate = 100;
    constexpr int frames = 64;
    constexpr int channels = 1;
    const int ctx = wajuce_context_create(sampleRate, 16, 0, channels);
    const int carrier = wajuce_create_constant_source(ctx);
    const int mod = wajuce_create_constant_source(ctx);
    const int comp = wajuce_create_compressor(ctx);
    const int dest = wajuce_context_get_destination_id(ctx);
    wajuce_param_set(carrier, "offset", 1.0f);
    wajuce_param_set(mod, "offset", 100.0f);
    wajuce_param_set(comp, "threshold", -100.0f);
    wajuce_param_set(comp, "knee", 0.0f);
    wajuce_param_set(comp, "ratio", 20.0f);
    wajuce_param_set(comp, "attack", 0.0001f);
    wajuce_param_set(comp, "release", 0.0001f);
    wajuce_connect(ctx, carrier, comp, 0, 0);
    wajuce_connect_param(ctx, mod, comp, "threshold", 0);
    wajuce_connect(ctx, comp, dest, 0, 0);
    wajuce_osc_start(carrier, 0.0);
    wajuce_osc_start(mod, 0.0);
    std::vector<float> out(static_cast<size_t>(frames * channels), 0.0f);
    wajuce_context_render(ctx, out.data(), frames, channels);
    ok &= expect(out[frames - 1] > 0.9f,
                 "AudioParam input should modulate compressor threshold");
    wajuce_context_destroy(ctx);
  }

  {
    constexpr int sampleRate = 100;
    constexpr int frames = 16;
    constexpr int channels = 1;
    const int ctx = wajuce_context_create(sampleRate, 16, 0, channels);
    const int src = wajuce_create_constant_source(ctx);
    const int mediaDest = wajuce_create_media_stream_destination(ctx);
    const int dest = wajuce_context_get_destination_id(ctx);
    wajuce_param_set(src, "offset", 1.0f);
    wajuce_connect(ctx, src, mediaDest, 0, 0);
    wajuce_connect(ctx, mediaDest, dest, 0, 0);
    wajuce_osc_start(src, 0.0);
    std::vector<float> out(static_cast<size_t>(frames * channels), 0.0f);
    wajuce_context_render(ctx, out.data(), frames, channels);
    ok &= expect(rms(out, frames, 0) < 0.0001,
                 "MediaStreamDestination should not expose an output");
    wajuce_context_destroy(ctx);
  }

  {
    constexpr int sampleRate = 100;
    constexpr int frames = 101;
    constexpr int channels = 1;
    const int ctx = wajuce_context_create(sampleRate, 16, 0, channels);
    const int src = wajuce_create_buffer_source(ctx);
    const int gain = wajuce_create_gain(ctx);
    const int dest = wajuce_context_get_destination_id(ctx);
    std::vector<float> ones(frames, 1.0f);
    const float curve[3] = {0.0f, 1.0f, 0.0f};
    wajuce_buffer_source_set_buffer(src, ones.data(), frames, 1, sampleRate);
    wajuce_param_set(src, "decay", 10000.0f);
    wajuce_param_set_value_curve(gain, "gain", curve, 3, 0.0, 1.0);
    wajuce_connect(ctx, src, gain, 0, 0);
    wajuce_connect(ctx, gain, dest, 0, 0);
    wajuce_buffer_source_start(src, 0.0);
    std::vector<float> out(static_cast<size_t>(frames), 0.0f);
    wajuce_context_render(ctx, out.data(), frames, channels);
    ok &= expect(out[0] < 0.01f && out[50] > 0.98f && out[100] < 0.02f,
                 "setValueCurveAtTime should interpolate over duration");
    wajuce_context_destroy(ctx);
  }

  {
    constexpr int sampleRate = 10;
    constexpr int frames = 4;
    constexpr int channels = 1;
    const int ctx = wajuce_context_create(sampleRate, 8, 0, channels);
    const int src = wajuce_create_buffer_source(ctx);
    const int dest = wajuce_context_get_destination_id(ctx);
    const float data[frames] = {1.0f, 1.0f, 1.0f, 1.0f};
    wajuce_buffer_source_set_buffer(src, data, frames, 1, sampleRate);
    wajuce_connect(ctx, src, dest, 0, 0);
    wajuce_buffer_source_start(src, 0.0);
    std::vector<float> out(static_cast<size_t>(frames), 0.0f);
    wajuce_context_render(ctx, out.data(), frames, channels);
    ok &= expect(near(out[0], 1.0f, 0.001f) &&
                     near(out[3], 1.0f, 0.001f),
                 "BufferSource default playback should not decay");
    wajuce_context_destroy(ctx);
  }

  {
    constexpr int sampleRate = 44100;
    constexpr int channels = 1;
    const float real[2] = {0.0f, 2.0f};
    const float imag[2] = {0.0f, 0.0f};

    int ctx = wajuce_context_create(sampleRate, 8, 0, channels);
    int osc = wajuce_create_oscillator(ctx);
    int dest = wajuce_context_get_destination_id(ctx);
    wajuce_osc_set_periodic_wave(osc, real, imag, 2, 0);
    wajuce_connect(ctx, osc, dest, 0, 0);
    wajuce_osc_start(osc, 0.0);
    std::vector<float> out(1, 0.0f);
    wajuce_context_render(ctx, out.data(), 1, channels);
    ok &= expect(out[0] > 0.99f && out[0] < 1.01f,
                 "PeriodicWave should normalize custom oscillator tables");
    wajuce_context_destroy(ctx);

    ctx = wajuce_context_create(sampleRate, 8, 0, channels);
    osc = wajuce_create_oscillator(ctx);
    dest = wajuce_context_get_destination_id(ctx);
    wajuce_osc_set_periodic_wave(osc, real, imag, 2, 1);
    wajuce_connect(ctx, osc, dest, 0, 0);
    wajuce_osc_start(osc, 0.0);
    std::fill(out.begin(), out.end(), 0.0f);
    wajuce_context_render(ctx, out.data(), 1, channels);
    ok &= expect(out[0] > 1.99f && out[0] < 2.01f,
                 "PeriodicWave disableNormalization should preserve amplitude");
    wajuce_context_destroy(ctx);
  }

  {
    constexpr int sampleRate = 44100;
    constexpr int frames = 44100;
    constexpr int channels = 1;
    const int ctx = wajuce_context_create(sampleRate, 128, 0, channels);
    const int src = wajuce_create_buffer_source(ctx);
    const int gain = wajuce_create_gain(ctx);
    const int dest = wajuce_context_get_destination_id(ctx);
    std::vector<float> ones(frames, 1.0f);
    wajuce_buffer_source_set_buffer(src, ones.data(), frames, 1, sampleRate);
    wajuce_param_set(src, "decay", 10000.0f);
    wajuce_param_set_at_time(gain, "gain", 0.0f, 0.0);
    wajuce_param_linear_ramp(gain, "gain", 1.0f, 1.0);
    wajuce_connect(ctx, src, gain, 0, 0);
    wajuce_connect(ctx, gain, dest, 0, 0);
    wajuce_buffer_source_start(src, 0.0);

    std::vector<float> out(static_cast<size_t>(frames * channels), 0.0f);
    wajuce_context_render(ctx, out.data(), frames, channels);
    ok &= expect(std::abs(out[0]) < 0.01f,
                 "linear ramp should start near the scheduled initial value");
    ok &= expect(out[22050] > 0.45f && out[22050] < 0.55f,
                 "linear ramp midpoint should be near 0.5");
    ok &= expect(out[44099] > 0.98f,
                 "linear ramp endpoint should approach target");
    wajuce_context_destroy(ctx);
  }

  {
    constexpr int sampleRate = 100;
    constexpr int frames = 101;
    constexpr int channels = 1;
    const int ctx = wajuce_context_create(sampleRate, 16, 0, channels);
    const int src = wajuce_create_buffer_source(ctx);
    const int gain = wajuce_create_gain(ctx);
    const int dest = wajuce_context_get_destination_id(ctx);
    std::vector<float> ones(frames, 1.0f);
    wajuce_buffer_source_set_buffer(src, ones.data(), frames, 1, sampleRate);
    wajuce_param_set_at_time(gain, "gain", 0.0f, 0.0);
    wajuce_param_linear_ramp(gain, "gain", 1.0f, 1.0);
    wajuce_param_cancel_and_hold(gain, "gain", 0.5);
    wajuce_connect(ctx, src, gain, 0, 0);
    wajuce_connect(ctx, gain, dest, 0, 0);
    wajuce_buffer_source_start(src, 0.0);
    std::vector<float> out(static_cast<size_t>(frames), 0.0f);
    wajuce_context_render(ctx, out.data(), frames, channels);
    ok &= expect(out[50] > 0.49f && out[50] < 0.51f &&
                     out[100] > 0.49f && out[100] < 0.51f,
                 "cancelAndHoldAtTime should hold interpolated ramp value");
    wajuce_context_destroy(ctx);
  }

  {
    constexpr int sampleRate = 44100;
    constexpr int frames = 2048;
    constexpr int channels = 1;
    const int ctx = wajuce_context_create(sampleRate, 128, 0, channels);
    const int src = wajuce_create_buffer_source(ctx);
    const int delay = wajuce_create_delay(ctx, 1.0f);
    const int dest = wajuce_context_get_destination_id(ctx);
    std::vector<float> impulse(64, 0.0f);
    impulse[0] = 1.0f;
    wajuce_buffer_source_set_buffer(src, impulse.data(),
                                    static_cast<int32_t>(impulse.size()), 1,
                                    sampleRate);
    wajuce_param_set(delay, "delayTime", 0.01f);
    wajuce_connect(ctx, src, delay, 0, 0);
    wajuce_connect(ctx, delay, dest, 0, 0);
    wajuce_buffer_source_start(src, 0.0);

    std::vector<float> out(static_cast<size_t>(frames * channels), 0.0f);
    wajuce_context_render(ctx, out.data(), frames, channels);
    const int peak = peakIndex(out, frames, 0);
    ok &= expect(std::abs(peak - 441) <= 1,
                 "delay should place an impulse at delayTime * sampleRate");
    wajuce_context_destroy(ctx);
  }

  {
    constexpr int sampleRate = 10;
    constexpr int frames = 5;
    constexpr int channels = 1;
    const int ctx = wajuce_context_create(sampleRate, 8, 0, channels);
    const int src = wajuce_create_buffer_source(ctx);
    const int delay = wajuce_create_delay(ctx, 1.0f);
    const int dest = wajuce_context_get_destination_id(ctx);
    const float impulse[1] = {1.0f};
    wajuce_buffer_source_set_buffer(src, impulse, 1, 1, sampleRate);
    wajuce_param_set(delay, "delayTime", 0.15f);
    wajuce_connect(ctx, src, delay, 0, 0);
    wajuce_connect(ctx, delay, dest, 0, 0);
    wajuce_buffer_source_start(src, 0.0);
    std::vector<float> out(static_cast<size_t>(frames), 0.0f);
    wajuce_context_render(ctx, out.data(), frames, channels);
    ok &= expect(near(out[1], 0.5f, 0.001f) &&
                     near(out[2], 0.5f, 0.001f),
                 "delayTime should support fractional-frame interpolation");
    wajuce_context_destroy(ctx);
  }

  {
    const int ctx = wajuce_context_create(44100, 128, 0, 1);
    const int delay = wajuce_create_delay(ctx, 1.0f);
    const int gain = wajuce_create_gain(ctx);
    wajuce_connect(ctx, delay, gain, 0, 0);
    wajuce_connect(ctx, gain, delay, 0, 0);
    ok &= expect(wajuce_context_get_feedback_bridge_count(ctx) > 0,
                 "cycle creation should be tracked as feedback");
    wajuce_context_destroy(ctx);
  }

  {
    constexpr int sampleRate = 44100;
    constexpr int frames = 2;
    constexpr int channels = 1;
    const int ctx = wajuce_context_create(sampleRate, 8, 0, channels);
    const int src = wajuce_create_buffer_source(ctx);
    const int shaper = wajuce_create_wave_shaper(ctx);
    const int dest = wajuce_context_get_destination_id(ctx);
    const float data[2] = {-1.0f, 1.0f};
    const float curve[3] = {1.0f, 0.0f, 1.0f};
    wajuce_buffer_source_set_buffer(src, data, 2, 1, sampleRate);
    wajuce_param_set(src, "decay", 10000.0f);
    wajuce_wave_shaper_set_curve(shaper, curve, 3);
    wajuce_wave_shaper_set_oversample(shaper, 2);
    wajuce_connect(ctx, src, shaper, 0, 0);
    wajuce_connect(ctx, shaper, dest, 0, 0);
    wajuce_buffer_source_start(src, 0.0);
    std::vector<float> out(static_cast<size_t>(frames), 0.0f);
    wajuce_context_render(ctx, out.data(), frames, channels);
    ok &= expect(out[0] > 0.45f && out[0] < 0.55f && out[1] > 0.99f,
                 "WaveShaper oversample should affect nonlinear transitions");
    wajuce_context_destroy(ctx);
  }

  {
    constexpr int sampleRate = 44100;
    constexpr int channels = 1;
    const int ctx = wajuce_context_create(sampleRate, 8, 0, channels);
    const int worklet = wajuce_create_worklet_bridge(ctx, 1, 1);
    const int dest = wajuce_context_get_destination_id(ctx);
    float *fromIsolate = wajuce_worklet_get_buffer_ptr(ctx, worklet, 1, 0);
    ok &= expect(fromIsolate != nullptr,
                 "WorkletBridge output ring should expose a native buffer");
    if (fromIsolate != nullptr) {
      fromIsolate[0] = 0.25f;
      fromIsolate[1] = 0.5f;
      wajuce_worklet_set_write_pos(ctx, worklet, 1, 0, 2);
    }
    wajuce_connect(ctx, worklet, dest, 0, 0);
    std::vector<float> out(4, 0.0f);
    wajuce_context_render(ctx, out.data(), 4, channels);
    ok &= expect(near(out[0], 0.25f, 0.001f) &&
                     near(out[1], 0.5f, 0.001f) &&
                     near(out[2], 0.5f, 0.001f) &&
                     near(out[3], 0.5f, 0.001f),
                 "WorkletBridge underrun should hold the last output sample");
    std::fill(out.begin(), out.end(), 0.0f);
    wajuce_context_render(ctx, out.data(), 3, channels);
    ok &= expect(near(out[0], 0.5f, 0.001f) &&
                     near(out[1], 0.5f, 0.001f) &&
                     near(out[2], 0.5f, 0.001f),
                 "WorkletBridge full underrun should continue held output");
    wajuce_context_destroy(ctx);
  }

  {
    constexpr int sampleRate = 44100;
    constexpr int frames = 4;
    constexpr int channels = 2;
    const int ctx = wajuce_context_create(sampleRate, 8, 1, channels);
    const int src = wajuce_create_media_stream_source(ctx);
    const int dest = wajuce_context_get_destination_id(ctx);
    const float input[frames] = {0.1f, 0.2f, 0.3f, 0.4f};
    wajuce_context_set_input_buffer(ctx, input, frames, 1);
    wajuce_connect(ctx, src, dest, 0, 0);
    std::vector<float> out(static_cast<size_t>(frames * channels), 0.0f);
    wajuce_context_render(ctx, out.data(), frames, channels);
    ok &= expect(near(out[0], 0.1f, 0.001f) &&
                     near(out[3], 0.4f, 0.001f) &&
                     near(out[frames], 0.1f, 0.001f) &&
                     near(out[frames + 3], 0.4f, 0.001f),
                 "MediaStreamSource should render injected mono input to stereo");
    wajuce_context_destroy(ctx);
  }

  {
    constexpr int sampleRate = 44100;
    constexpr int frames = 128;
    constexpr int channels = 1;
    const int ctx = wajuce_context_create(sampleRate, 128, 0, channels);
    const int src = wajuce_create_constant_source(ctx);
    const int dest = wajuce_context_get_destination_id(ctx);
    wajuce_param_set(src, "offset", 0.5f);
    wajuce_connect(ctx, src, dest, 0, 0);
    wajuce_osc_start(src, 0.0);
    std::vector<float> out(static_cast<size_t>(frames), 0.0f);
    wajuce_context_render(ctx, out.data(), frames, channels);
    ok &= expect(near(out[0], 0.5f, 0.0001f) &&
                     near(out[frames - 1], 0.5f, 0.0001f),
                 "constant source should output scheduled offset");
    wajuce_context_destroy(ctx);
  }

  {
    constexpr int sampleRate = 44100;
    constexpr int frames = 4;
    constexpr int channels = 2;
    const int ctx = wajuce_context_create(sampleRate, 8, 0, channels);
    const int src = wajuce_create_buffer_source(ctx);
    const int splitter = wajuce_create_channel_splitter(ctx, 2);
    const int dest = wajuce_context_get_destination_id(ctx);
    const float data[frames * channels] = {0.1f, 0.2f, 0.3f, 0.4f,
                                           0.6f, 0.7f, 0.8f, 0.9f};
    wajuce_buffer_source_set_buffer(src, data, frames, channels, sampleRate);
    wajuce_param_set(src, "decay", 10000.0f);
    wajuce_connect(ctx, src, splitter, 0, 0);
    wajuce_connect(ctx, splitter, dest, 1, 0);
    wajuce_buffer_source_start(src, 0.0);
    std::vector<float> out(static_cast<size_t>(frames * channels), 0.0f);
    wajuce_context_render(ctx, out.data(), frames, channels);
    ok &= expect(near(out[0], 0.6f, 0.001f) &&
                     near(out[3], 0.9f, 0.001f) &&
                     near(out[frames], 0.0f, 0.001f),
                 "ChannelSplitter output index should select source channel");
    wajuce_context_destroy(ctx);
  }

  {
    constexpr int sampleRate = 44100;
    constexpr int frames = 4;
    constexpr int channels = 2;
    const int ctx = wajuce_context_create(sampleRate, 8, 0, channels);
    const int left = wajuce_create_constant_source(ctx);
    const int right = wajuce_create_constant_source(ctx);
    const int merger = wajuce_create_channel_merger(ctx, 2);
    const int dest = wajuce_context_get_destination_id(ctx);
    wajuce_param_set(left, "offset", 0.25f);
    wajuce_param_set(right, "offset", 0.75f);
    wajuce_connect(ctx, left, merger, 0, 0);
    wajuce_connect(ctx, right, merger, 0, 1);
    wajuce_connect(ctx, merger, dest, 0, 0);
    wajuce_osc_start(left, 0.0);
    wajuce_osc_start(right, 0.0);
    std::vector<float> out(static_cast<size_t>(frames * channels), 0.0f);
    wajuce_context_render(ctx, out.data(), frames, channels);
    ok &= expect(near(out[0], 0.25f, 0.001f) &&
                     near(out[frames], 0.75f, 0.001f),
                 "ChannelMerger input index should write destination channel");
    wajuce_context_destroy(ctx);
  }

  {
    constexpr int sampleRate = 10;
    constexpr int frames = 8;
    constexpr int channels = 1;
    const int ctx = wajuce_context_create(sampleRate, 8, 0, channels);
    const int src = wajuce_create_buffer_source(ctx);
    const int dest = wajuce_context_get_destination_id(ctx);
    const float data[10] = {0.0f, 1.0f, 2.0f, 3.0f, 4.0f,
                            5.0f, 6.0f, 7.0f, 8.0f, 9.0f};
    wajuce_buffer_source_set_buffer(src, data, 10, 1, sampleRate);
    wajuce_param_set(src, "decay", 10000.0f);
    wajuce_connect(ctx, src, dest, 0, 0);
    wajuce_buffer_source_start_with_offset(src, 0.0, 0.2, 0.3, 1);
    std::vector<float> out(static_cast<size_t>(frames), 0.0f);
    wajuce_context_render(ctx, out.data(), frames, channels);
    ok &= expect(near(out[0], 2.0f, 0.001f) &&
                     near(out[1], 3.0f, 0.001f) &&
                     near(out[2], 4.0f, 0.001f) &&
                     near(out[3], 0.0f, 0.001f),
                 "buffer source start offset/duration should match WebAudio");
    wajuce_context_destroy(ctx);
  }

  {
    constexpr int sampleRate = 10;
    constexpr int frames = 6;
    constexpr int channels = 1;
    const int ctx = wajuce_context_create(sampleRate, 8, 0, channels);
    const int src = wajuce_create_buffer_source(ctx);
    const int dest = wajuce_context_get_destination_id(ctx);
    const float data[5] = {0.0f, 1.0f, 2.0f, 3.0f, 4.0f};
    wajuce_buffer_source_set_buffer(src, data, 5, 1, sampleRate);
    wajuce_param_set(src, "decay", 10000.0f);
    wajuce_buffer_source_set_loop(src, 1);
    wajuce_buffer_source_set_loop_points(src, 0.1, 0.4);
    wajuce_connect(ctx, src, dest, 0, 0);
    wajuce_buffer_source_start(src, 0.0);
    std::vector<float> out(static_cast<size_t>(frames), 0.0f);
    wajuce_context_render(ctx, out.data(), frames, channels);
    ok &= expect(near(out[0], 0.0f, 0.001f) &&
                     near(out[1], 1.0f, 0.001f) &&
                     near(out[2], 2.0f, 0.001f) &&
                     near(out[3], 3.0f, 0.001f) &&
                     near(out[4], 1.0f, 0.001f),
                 "buffer source loop points should wrap inside loop range");
    wajuce_context_destroy(ctx);
  }

  {
    constexpr int sampleRate = 10;
    constexpr int frames = 6;
    constexpr int channels = 1;
    const int ctx = wajuce_context_create(sampleRate, 8, 0, channels);
    const int src = wajuce_create_buffer_source(ctx);
    const int delay = wajuce_create_delay(ctx, 1.0f);
    const int dest = wajuce_context_get_destination_id(ctx);
    const float impulse[1] = {1.0f};
    wajuce_buffer_source_set_buffer(src, impulse, 1, 1, sampleRate);
    wajuce_param_set(src, "decay", 10000.0f);
    wajuce_param_set(delay, "delayTime", 0.1f);
    wajuce_param_set(delay, "feedback", 0.5f);
    wajuce_connect(ctx, src, delay, 0, 0);
    wajuce_connect(ctx, delay, dest, 0, 0);
    wajuce_buffer_source_start(src, 0.0);
    std::vector<float> out(static_cast<size_t>(frames), 0.0f);
    wajuce_context_render(ctx, out.data(), frames, channels);
    ok &= expect(near(out[1], 1.0f, 0.001f) &&
                     near(out[2], 0.5f, 0.001f) &&
                     near(out[3], 0.25f, 0.001f),
                 "delay feedback parameter should feed the wet delay line");
    wajuce_context_destroy(ctx);
  }

  {
    constexpr int sampleRate = 44100;
    constexpr int frames = 8;
    constexpr int channels = 1;
    const int ctx = wajuce_context_create(sampleRate, 8, 0, channels);
    const int src = wajuce_create_buffer_source(ctx);
    const int conv = wajuce_create_convolver(ctx);
    const int dest = wajuce_context_get_destination_id(ctx);
    const float impulse[1] = {1.0f};
    const float ir[2] = {0.25f, 0.5f};
    wajuce_buffer_source_set_buffer(src, impulse, 1, 1, sampleRate);
    wajuce_param_set(src, "decay", 10000.0f);
    wajuce_convolver_set_buffer(conv, ir, 2, 1, sampleRate, 0);
    wajuce_connect(ctx, src, conv, 0, 0);
    wajuce_connect(ctx, conv, dest, 0, 0);
    wajuce_buffer_source_start(src, 0.0);
    std::vector<float> out(static_cast<size_t>(frames), 0.0f);
    wajuce_context_render(ctx, out.data(), frames, channels);
    ok &= expect(near(out[0], 0.25f, 0.001f) &&
                     near(out[1], 0.5f, 0.001f),
                 "convolver should render a supplied impulse response");
    wajuce_context_destroy(ctx);
  }

  {
    constexpr int sampleRate = 44100;
    constexpr int frames = 4;
    constexpr int channels = 1;
    const int ctx = wajuce_context_create(sampleRate, 8, 0, channels);
    const int src = wajuce_create_buffer_source(ctx);
    const double ff[2] = {1.0, -1.0};
    const double fb[1] = {1.0};
    const int iir = wajuce_create_iir_filter(ctx, ff, 2, fb, 1);
    const int dest = wajuce_context_get_destination_id(ctx);
    const float data[4] = {1.0f, 2.0f, 4.0f, 8.0f};
    wajuce_buffer_source_set_buffer(src, data, 4, 1, sampleRate);
    wajuce_param_set(src, "decay", 10000.0f);
    wajuce_connect(ctx, src, iir, 0, 0);
    wajuce_connect(ctx, iir, dest, 0, 0);
    wajuce_buffer_source_start(src, 0.0);
    std::vector<float> out(static_cast<size_t>(frames), 0.0f);
    wajuce_context_render(ctx, out.data(), frames, channels);
    ok &= expect(near(out[0], 1.0f, 0.001f) &&
                     near(out[1], 1.0f, 0.001f) &&
                     near(out[2], 2.0f, 0.001f),
                 "IIR filter should apply feedforward/feedback coefficients");
    wajuce_context_destroy(ctx);
  }

  {
    const int ctx = wajuce_context_create(10, 8, 0, 1);
    const double ff[2] = {1.0, -1.0};
    const double fb[1] = {1.0};
    const int iir = wajuce_create_iir_filter(ctx, ff, 2, fb, 1);
    const float freq[2] = {0.0f, 5.0f};
    float mag[2] = {1.0f, 0.0f};
    float phase[2] = {1.0f, 1.0f};
    wajuce_iir_get_frequency_response(iir, freq, mag, phase, 2);
    ok &= expect(mag[0] < 0.001f && mag[1] > 1.99f && mag[1] < 2.01f,
                 "IIR frequency response should use native context sample rate");
    wajuce_context_destroy(ctx);
  }

  {
    const int ctx = wajuce_context_create(44100, 128, 0, 1);
    const int biquad = wajuce_create_biquad_filter(ctx);
    const float freq[1] = {0.0f};
    float mag[1] = {0.0f};
    float phase[1] = {1.0f};
    wajuce_biquad_get_frequency_response(biquad, freq, mag, phase, 1);
    ok &= expect(mag[0] > 0.95f && mag[0] < 1.05f &&
                     std::abs(phase[0]) < 0.001f,
                 "biquad frequency response should report DC gain");
    wajuce_context_destroy(ctx);
  }

  {
    constexpr int sampleRate = 44100;
    constexpr int frames = 2048;
    constexpr int channels = 1;
    const int ctx = wajuce_context_create(sampleRate, 128, 0, channels);
    const int src = wajuce_create_buffer_source(ctx);
    const int comp = wajuce_create_compressor(ctx);
    const int dest = wajuce_context_get_destination_id(ctx);
    std::vector<float> loud(static_cast<size_t>(frames), 1.0f);
    wajuce_buffer_source_set_buffer(src, loud.data(), frames, 1, sampleRate);
    wajuce_param_set(src, "decay", 10000.0f);
    wajuce_param_set(comp, "attack", 0.0001f);
    wajuce_connect(ctx, src, comp, 0, 0);
    wajuce_connect(ctx, comp, dest, 0, 0);
    wajuce_buffer_source_start(src, 0.0);
    std::vector<float> out(static_cast<size_t>(frames), 0.0f);
    wajuce_context_render(ctx, out.data(), frames, channels);
    ok &= expect(wajuce_compressor_get_reduction(comp) < -1.0f,
                 "compressor reduction should expose current gain reduction");
    wajuce_context_destroy(ctx);
  }

  {
    constexpr int sampleRate = 44100;
    constexpr int frames = 128;
    constexpr int channels = 2;
    const int ctx = wajuce_context_create(sampleRate, 128, 0, channels);
    const int listener = wajuce_context_get_listener_id(ctx);
    const int src = wajuce_create_constant_source(ctx);
    const int panner = wajuce_create_panner(ctx);
    const int dest = wajuce_context_get_destination_id(ctx);
    wajuce_param_set(listener, "positionX", 0.0f);
    wajuce_param_set(src, "offset", 1.0f);
    wajuce_param_set(panner, "positionX", 1.0f);
    wajuce_param_set(panner, "positionZ", 0.0f);
    wajuce_connect(ctx, src, panner, 0, 0);
    wajuce_connect(ctx, panner, dest, 0, 0);
    wajuce_osc_start(src, 0.0);
    std::vector<float> out(static_cast<size_t>(frames * channels), 0.0f);
    wajuce_context_render(ctx, out.data(), frames, channels);
    ok &= expect(std::abs(out[0]) < 0.05f && out[frames] > 0.9f,
                 "PannerNode should pan a right-side source to the right");
    wajuce_context_destroy(ctx);
  }

  {
    constexpr int sampleRate = 44100;
    constexpr int frames = 128;
    constexpr int channels = 2;
    const int ctx = wajuce_context_create(sampleRate, 128, 0, channels);
    const int src = wajuce_create_constant_source(ctx);
    const int panner = wajuce_create_panner(ctx);
    const int dest = wajuce_context_get_destination_id(ctx);
    wajuce_param_set(src, "offset", 1.0f);
    wajuce_param_set(panner, "positionZ", 10.0f);
    wajuce_panner_set_distance_model(panner, 1);
    wajuce_panner_set_ref_distance(panner, 1.0);
    wajuce_panner_set_rolloff_factor(panner, 1.0);
    wajuce_connect(ctx, src, panner, 0, 0);
    wajuce_connect(ctx, panner, dest, 0, 0);
    wajuce_osc_start(src, 0.0);
    std::vector<float> out(static_cast<size_t>(frames * channels), 0.0f);
    wajuce_context_render(ctx, out.data(), frames, channels);
    ok &= expect(out[0] > 0.06f && out[0] < 0.08f &&
                     out[frames] > 0.06f && out[frames] < 0.08f,
                 "PannerNode inverse distance attenuation should reduce gain");
    wajuce_context_destroy(ctx);
  }

  {
    constexpr int sampleRate = 44100;
    constexpr int frames = 128;
    constexpr int channels = 2;
    const int ctx = wajuce_context_create(sampleRate, 128, 0, channels);
    const int src = wajuce_create_constant_source(ctx);
    const int panner = wajuce_create_panner(ctx);
    const int dest = wajuce_context_get_destination_id(ctx);
    wajuce_param_set(src, "offset", 1.0f);
    wajuce_param_set(panner, "positionZ", 1.0f);
    wajuce_param_set(panner, "orientationX", 1.0f);
    wajuce_param_set(panner, "orientationZ", 0.0f);
    wajuce_panner_set_cone_inner_angle(panner, 30.0);
    wajuce_panner_set_cone_outer_angle(panner, 60.0);
    wajuce_panner_set_cone_outer_gain(panner, 0.25);
    wajuce_connect(ctx, src, panner, 0, 0);
    wajuce_connect(ctx, panner, dest, 0, 0);
    wajuce_osc_start(src, 0.0);
    std::vector<float> out(static_cast<size_t>(frames * channels), 0.0f);
    wajuce_context_render(ctx, out.data(), frames, channels);
    ok &= expect(out[0] > 0.16f && out[0] < 0.19f &&
                     out[frames] > 0.16f && out[frames] < 0.19f,
                 "PannerNode cone attenuation should affect rendered gain");
    wajuce_context_destroy(ctx);
  }

  {
    std::vector<uint8_t> wav;
    putTag(wav, "RIFF");
    putLE32(wav, 39);
    putTag(wav, "WAVE");
    putTag(wav, "fmt ");
    putLE32(wav, 16);
    putLE16(wav, 1);
    putLE16(wav, 1);
    putLE32(wav, 8000);
    putLE32(wav, 8000);
    putLE16(wav, 1);
    putLE16(wav, 8);
    putTag(wav, "data");
    putLE32(wav, 3);
    wav.push_back(0);
    wav.push_back(128);
    wav.push_back(255);
    int32_t frames = 0;
    int32_t channels = 0;
    int32_t sr = 0;
    ok &= expect(wajuce_decode_audio_data(wav.data(), wav.size(), nullptr,
                                          &frames, &channels, &sr) == 0 &&
                     frames == 3 && channels == 1 && sr == 8000,
                 "decodeAudioData should report WAV dimensions");
    std::vector<float> decoded(static_cast<size_t>(frames * channels), 0.0f);
    ok &= expect(wajuce_decode_audio_data(wav.data(), wav.size(),
                                          decoded.data(), &frames, &channels,
                                          &sr) == 0 &&
                     near(decoded[0], -1.0f, 0.001f) &&
                     near(decoded[1], 0.0f, 0.001f),
                 "decodeAudioData should decode unsigned 8-bit WAV PCM");
  }

  {
    std::vector<uint8_t> wav;
    putTag(wav, "RIFF");
    putLE32(wav, 52);
    putTag(wav, "WAVE");
    putTag(wav, "fmt ");
    putLE32(wav, 16);
    putLE16(wav, 3);
    putLE16(wav, 1);
    putLE32(wav, 8000);
    putLE32(wav, 8000 * 8);
    putLE16(wav, 8);
    putLE16(wav, 64);
    putTag(wav, "data");
    putLE32(wav, 16);
    putLEFloat64(wav, -1.0);
    putLEFloat64(wav, 0.5);
    int32_t frames = 0;
    int32_t channels = 0;
    int32_t sr = 0;
    std::vector<float> decoded(2, 0.0f);
    ok &= expect(wajuce_decode_audio_data(wav.data(), wav.size(),
                                          decoded.data(), &frames, &channels,
                                          &sr) == 0 &&
                     frames == 2 && channels == 1 && sr == 8000 &&
                     near(decoded[0], -1.0f, 0.001f) &&
                     near(decoded[1], 0.5f, 0.001f),
                 "decodeAudioData should decode 64-bit float WAV");
  }

  {
    std::vector<uint8_t> aiff;
    putTag(aiff, "FORM");
    putBE32(aiff, 50);
    putTag(aiff, "AIFF");
    putTag(aiff, "COMM");
    putBE32(aiff, 18);
    putBE16(aiff, 1);
    putBE32(aiff, 2);
    putBE16(aiff, 16);
    const uint8_t sr44100[10] = {0x40, 0x0E, 0xAC, 0x44, 0x00,
                                 0x00, 0x00, 0x00, 0x00, 0x00};
    aiff.insert(aiff.end(), sr44100, sr44100 + 10);
    putTag(aiff, "SSND");
    putBE32(aiff, 12);
    putBE32(aiff, 0);
    putBE32(aiff, 0);
    aiff.push_back(0x80);
    aiff.push_back(0x00);
    aiff.push_back(0x7F);
    aiff.push_back(0xFF);
    int32_t frames = 0;
    int32_t channels = 0;
    int32_t sr = 0;
    std::vector<float> decoded(2, 0.0f);
    ok &= expect(wajuce_decode_audio_data(aiff.data(), aiff.size(),
                                          decoded.data(), &frames, &channels,
                                          &sr) == 0 &&
                     frames == 2 && channels == 1 && sr == 44100 &&
                     near(decoded[0], -1.0f, 0.001f) &&
                     decoded[1] > 0.99f,
                 "decodeAudioData should decode AIFF PCM");
  }

  {
    std::vector<uint8_t> aifc;
    putTag(aifc, "FORM");
    putBE32(aifc, 58);
    putTag(aifc, "AIFC");
    putTag(aifc, "COMM");
    putBE32(aifc, 22);
    putBE16(aifc, 1);
    putBE32(aifc, 2);
    putBE16(aifc, 32);
    const uint8_t sr44100[10] = {0x40, 0x0E, 0xAC, 0x44, 0x00,
                                 0x00, 0x00, 0x00, 0x00, 0x00};
    aifc.insert(aifc.end(), sr44100, sr44100 + 10);
    putTag(aifc, "fl32");
    putTag(aifc, "SSND");
    putBE32(aifc, 16);
    putBE32(aifc, 0);
    putBE32(aifc, 0);
    putBEFloat32(aifc, -0.25f);
    putBEFloat32(aifc, 0.75f);
    int32_t frames = 0;
    int32_t channels = 0;
    int32_t sr = 0;
    std::vector<float> decoded(2, 0.0f);
    ok &= expect(wajuce_decode_audio_data(aifc.data(), aifc.size(),
                                          decoded.data(), &frames, &channels,
                                          &sr) == 0 &&
                     frames == 2 && channels == 1 && sr == 44100 &&
                     near(decoded[0], -0.25f, 0.001f) &&
                     near(decoded[1], 0.75f, 0.001f),
                 "decodeAudioData should decode AIFC float32 PCM");
  }

  if (!ok) {
    return 1;
  }
  std::puts("PASS: webaudio_render_smoke");
  return 0;
}
