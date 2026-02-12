/**
 * wajuce.c — C stub implementation (no JUCE dependency).
 *
 * Used when WAJUCE_STUB_ONLY=ON. Provides all C-API symbols with minimal
 * implementations so Dart FFI binding generation and analysis works
 * without requiring the JUCE SDK.
 */

#include "wajuce.h"
#include <string.h>

static int32_t next_id = 1;

// ============================================================================
// Context
// ============================================================================

FFI_PLUGIN_EXPORT int32_t wajuce_context_create(int32_t sample_rate,
                                                int32_t buffer_size) {
  return next_id++;
}

FFI_PLUGIN_EXPORT void wajuce_context_destroy(int32_t ctx_id) {}

FFI_PLUGIN_EXPORT double wajuce_context_get_time(int32_t ctx_id) { return 0.0; }

FFI_PLUGIN_EXPORT double wajuce_context_get_sample_rate(int32_t ctx_id) {
  return 44100.0;
}

FFI_PLUGIN_EXPORT int32_t wajuce_context_get_state(int32_t ctx_id) { return 0; }

FFI_PLUGIN_EXPORT void wajuce_context_resume(int32_t ctx_id) {}
FFI_PLUGIN_EXPORT void wajuce_context_suspend(int32_t ctx_id) {}
FFI_PLUGIN_EXPORT void wajuce_context_close(int32_t ctx_id) {}

FFI_PLUGIN_EXPORT int32_t wajuce_context_get_destination_id(int32_t ctx_id) {
  return 0;
}

// ============================================================================
// Node factory
// ============================================================================

FFI_PLUGIN_EXPORT int32_t wajuce_create_gain(int32_t ctx_id) {
  return next_id++;
}

FFI_PLUGIN_EXPORT int32_t wajuce_create_oscillator(int32_t ctx_id) {
  return next_id++;
}

FFI_PLUGIN_EXPORT int32_t wajuce_create_biquad_filter(int32_t ctx_id) {
  return next_id++;
}

FFI_PLUGIN_EXPORT int32_t wajuce_create_compressor(int32_t ctx_id) {
  return next_id++;
}

FFI_PLUGIN_EXPORT int32_t wajuce_create_delay(int32_t ctx_id, float max_delay) {
  return next_id++;
}

FFI_PLUGIN_EXPORT int32_t wajuce_create_buffer_source(int32_t ctx_id) {
  return next_id++;
}

FFI_PLUGIN_EXPORT int32_t wajuce_create_analyser(int32_t ctx_id) {
  return next_id++;
}

FFI_PLUGIN_EXPORT int32_t wajuce_create_stereo_panner(int32_t ctx_id) {
  return next_id++;
}

FFI_PLUGIN_EXPORT int32_t wajuce_create_wave_shaper(int32_t ctx_id) {
  return next_id++;
}

FFI_PLUGIN_EXPORT int32_t wajuce_create_media_stream_source(int32_t ctx_id) {
  return next_id++;
}

FFI_PLUGIN_EXPORT int32_t
wajuce_create_media_stream_destination(int32_t ctx_id) {
  return next_id++;
}

// ============================================================================
// Graph
// ============================================================================

FFI_PLUGIN_EXPORT void wajuce_connect(int32_t ctx_id, int32_t src_id,
                                      int32_t dst_id, int32_t output,
                                      int32_t input) {}

FFI_PLUGIN_EXPORT void wajuce_disconnect(int32_t ctx_id, int32_t src_id,
                                         int32_t dst_id) {}

FFI_PLUGIN_EXPORT void wajuce_disconnect_all(int32_t ctx_id, int32_t src_id) {}

// ============================================================================
// Params
// ============================================================================

FFI_PLUGIN_EXPORT void wajuce_param_set(int32_t node_id, const char *param,
                                        float value) {}

FFI_PLUGIN_EXPORT void wajuce_param_set_at_time(int32_t node_id,
                                                const char *param, float value,
                                                double time) {}

FFI_PLUGIN_EXPORT void wajuce_param_linear_ramp(int32_t node_id,
                                                const char *param, float value,
                                                double end_time) {}

FFI_PLUGIN_EXPORT void wajuce_param_exp_ramp(int32_t node_id, const char *param,
                                             float value, double end_time) {}

FFI_PLUGIN_EXPORT void wajuce_param_set_target(int32_t node_id,
                                               const char *param, float target,
                                               double start_time, float tc) {}

FFI_PLUGIN_EXPORT void wajuce_param_cancel(int32_t node_id, const char *param,
                                           double cancel_time) {}

// ============================================================================
// Oscillator
// ============================================================================

FFI_PLUGIN_EXPORT void wajuce_osc_set_type(int32_t node_id, int32_t type) {}
FFI_PLUGIN_EXPORT void wajuce_osc_start(int32_t node_id, double when) {}
FFI_PLUGIN_EXPORT void wajuce_osc_stop(int32_t node_id, double when) {}

// ============================================================================
// Filter
// ============================================================================

FFI_PLUGIN_EXPORT void wajuce_filter_set_type(int32_t node_id, int32_t type) {}

// ============================================================================
// BufferSource
// ============================================================================

FFI_PLUGIN_EXPORT void
wajuce_buffer_source_set_buffer(int32_t node_id, const float *data,
                                int32_t frames, int32_t channels, int32_t sr) {}

FFI_PLUGIN_EXPORT void wajuce_buffer_source_start(int32_t node_id,
                                                  double when) {}

FFI_PLUGIN_EXPORT void wajuce_buffer_source_stop(int32_t node_id, double when) {
}

FFI_PLUGIN_EXPORT void wajuce_buffer_source_set_loop(int32_t node_id,
                                                     int32_t loop) {}

// ============================================================================
// Analyser
// ============================================================================

FFI_PLUGIN_EXPORT void wajuce_analyser_set_fft_size(int32_t node_id,
                                                    int32_t size) {}

FFI_PLUGIN_EXPORT void
wajuce_analyser_get_byte_freq(int32_t node_id, uint8_t *data, int32_t len) {
  if (data)
    memset(data, 0, len);
}

FFI_PLUGIN_EXPORT void
wajuce_analyser_get_byte_time(int32_t node_id, uint8_t *data, int32_t len) {
  if (data)
    memset(data, 128, len);
}

FFI_PLUGIN_EXPORT void
wajuce_analyser_get_float_freq(int32_t node_id, float *data, int32_t len) {
  if (data)
    memset(data, 0, len * sizeof(float));
}

FFI_PLUGIN_EXPORT void
wajuce_analyser_get_float_time(int32_t node_id, float *data, int32_t len) {
  if (data)
    memset(data, 0, len * sizeof(float));
}

// ============================================================================
// WaveShaper
// ============================================================================

FFI_PLUGIN_EXPORT void
wajuce_wave_shaper_set_curve(int32_t node_id, const float *data, int32_t len) {}

FFI_PLUGIN_EXPORT void wajuce_wave_shaper_set_oversample(int32_t node_id,
                                                         int32_t type) {}

// ============================================================================
// WorkletBridge
// ============================================================================

FFI_PLUGIN_EXPORT int32_t wajuce_create_worklet_bridge(int32_t ctx_id,
                                                       int32_t num_inputs,
                                                       int32_t num_outputs) {
  return -1;
}

FFI_PLUGIN_EXPORT void *wajuce_get_ring_buffer_ptr(int32_t bridge_id) {
  return (void *)0;
}

// ============================================================================
// MIDI
// ============================================================================

FFI_PLUGIN_EXPORT int32_t wajuce_midi_get_port_count(int32_t type) { return 0; }

FFI_PLUGIN_EXPORT void wajuce_midi_get_port_name(int32_t type, int32_t index,
                                                 char *buffer,
                                                 int32_t max_len) {
  if (buffer && max_len > 0)
    buffer[0] = '\0';
}

FFI_PLUGIN_EXPORT void wajuce_midi_port_open(int32_t type, int32_t index) {}
FFI_PLUGIN_EXPORT void wajuce_midi_port_close(int32_t type, int32_t index) {}

FFI_PLUGIN_EXPORT void wajuce_midi_output_send(int32_t index,
                                               const uint8_t *data, int32_t len,
                                               double timestamp) {}

FFI_PLUGIN_EXPORT int32_t wajuce_decode_audio_data(const uint8_t *encoded_data,
                                                   int32_t len, float *out_data,
                                                   int32_t *out_frames,
                                                   int32_t *out_channels,
                                                   int32_t *out_sr) {
  return -1;
}
