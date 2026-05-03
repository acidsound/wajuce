/**
 * wajuce.c — C stub implementation.
 *
 * Used when WAJUCE_STUB_ONLY=ON. Provides all C-API symbols with minimal
 * implementations so Dart FFI binding generation and analysis works
 * without requiring the native audio runtime.
 */

#include "wajuce.h"
#include <string.h>

static int32_t next_id = 1;

// ============================================================================
// Context
// ============================================================================

FFI_PLUGIN_EXPORT int32_t wajuce_context_create(int32_t sample_rate,
                                                int32_t buffer_size,
                                                int32_t input_channels,
                                                int32_t output_channels) {
  return next_id++;
}

FFI_PLUGIN_EXPORT void wajuce_context_destroy(int32_t ctx_id) {}

FFI_PLUGIN_EXPORT double wajuce_context_get_time(int32_t ctx_id) { return 0.0; }

FFI_PLUGIN_EXPORT int32_t wajuce_context_get_live_node_count(int32_t ctx_id) {
  return 0;
}

FFI_PLUGIN_EXPORT int32_t
wajuce_context_get_feedback_bridge_count(int32_t ctx_id) {
  return 0;
}

FFI_PLUGIN_EXPORT int32_t
wajuce_context_get_machine_voice_group_count(int32_t ctx_id) {
  return 0;
}

FFI_PLUGIN_EXPORT double wajuce_context_get_sample_rate(int32_t ctx_id) {
  return 44100.0;
}

FFI_PLUGIN_EXPORT int32_t wajuce_context_get_bit_depth(int32_t ctx_id) {
  return 32;
}

FFI_PLUGIN_EXPORT int32_t
wajuce_context_set_preferred_sample_rate(int32_t ctx_id,
                                         double preferred_sample_rate) {
  return 0;
}

FFI_PLUGIN_EXPORT int32_t
wajuce_context_set_preferred_bit_depth(int32_t ctx_id,
                                       int32_t preferred_bit_depth) {
  return 0;
}

FFI_PLUGIN_EXPORT int32_t wajuce_context_get_state(int32_t ctx_id) { return 0; }

FFI_PLUGIN_EXPORT void wajuce_context_resume(int32_t ctx_id) {}
FFI_PLUGIN_EXPORT void wajuce_context_suspend(int32_t ctx_id) {}
FFI_PLUGIN_EXPORT void wajuce_context_close(int32_t ctx_id) {}

FFI_PLUGIN_EXPORT int32_t wajuce_context_get_destination_id(int32_t ctx_id) {
  return 0;
}

FFI_PLUGIN_EXPORT int32_t wajuce_context_get_listener_id(int32_t ctx_id) {
  return next_id++;
}

FFI_PLUGIN_EXPORT int32_t wajuce_context_render(int32_t ctx_id,
                                                float *out_data,
                                                int32_t frames,
                                                int32_t channels) {
  if (out_data && frames > 0 && channels > 0) {
    memset(out_data, 0, (size_t)frames * (size_t)channels * sizeof(float));
  }
  return frames;
}

FFI_PLUGIN_EXPORT void wajuce_context_set_input_buffer(int32_t ctx_id,
                                                       const float *input_data,
                                                       int32_t frames,
                                                       int32_t channels) {}

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

FFI_PLUGIN_EXPORT int32_t wajuce_create_panner(int32_t ctx_id) {
  return next_id++;
}

FFI_PLUGIN_EXPORT int32_t wajuce_create_wave_shaper(int32_t ctx_id) {
  return next_id++;
}

FFI_PLUGIN_EXPORT int32_t wajuce_create_constant_source(int32_t ctx_id) {
  return next_id++;
}

FFI_PLUGIN_EXPORT int32_t wajuce_create_convolver(int32_t ctx_id) {
  return next_id++;
}

FFI_PLUGIN_EXPORT int32_t
wajuce_create_iir_filter(int32_t ctx_id, const double *feedforward,
                         int32_t feedforward_len, const double *feedback,
                         int32_t feedback_len) {
  return next_id++;
}

FFI_PLUGIN_EXPORT int32_t wajuce_create_media_stream_source(int32_t ctx_id) {
  return next_id++;
}

FFI_PLUGIN_EXPORT int32_t
wajuce_create_media_stream_destination(int32_t ctx_id) {
  return next_id++;
}

FFI_PLUGIN_EXPORT int32_t wajuce_create_channel_splitter(int32_t ctx_id,
                                                         int32_t outputs) {
  return next_id++;
}

FFI_PLUGIN_EXPORT int32_t wajuce_create_channel_merger(int32_t ctx_id,
                                                       int32_t inputs) {
  return next_id++;
}

FFI_PLUGIN_EXPORT void wajuce_create_machine_voice(int32_t ctx_id,
                                                   int32_t *result_ids) {
  if (!result_ids) {
    return;
  }
  for (int i = 0; i < 7; ++i) {
    result_ids[i] = next_id++;
  }
}

FFI_PLUGIN_EXPORT void wajuce_context_remove_node(int32_t ctx_id,
                                                  int32_t node_id) {}

// ============================================================================
// Graph
// ============================================================================

FFI_PLUGIN_EXPORT void wajuce_connect(int32_t ctx_id, int32_t src_id,
                                      int32_t dst_id, int32_t output,
                                      int32_t input) {}

FFI_PLUGIN_EXPORT void wajuce_connect_param(int32_t ctx_id, int32_t src_id,
                                            int32_t dst_id, const char *param,
                                            int32_t output) {}

FFI_PLUGIN_EXPORT void wajuce_disconnect(int32_t ctx_id, int32_t src_id,
                                         int32_t dst_id) {}

FFI_PLUGIN_EXPORT void wajuce_disconnect_output(int32_t ctx_id, int32_t src_id,
                                                int32_t output) {}

FFI_PLUGIN_EXPORT void wajuce_disconnect_node_output(
    int32_t ctx_id, int32_t src_id, int32_t dst_id, int32_t output) {}

FFI_PLUGIN_EXPORT void wajuce_disconnect_node_input(
    int32_t ctx_id, int32_t src_id, int32_t dst_id, int32_t output,
    int32_t input) {}

FFI_PLUGIN_EXPORT void wajuce_disconnect_param(int32_t ctx_id, int32_t src_id,
                                               int32_t dst_id,
                                               const char *param,
                                               int32_t output) {}

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

FFI_PLUGIN_EXPORT void wajuce_param_set_value_curve(
    int32_t node_id, const char *param, const float *values, int32_t length,
    double start_time, double duration) {}

FFI_PLUGIN_EXPORT void wajuce_param_cancel(int32_t node_id, const char *param,
                                           double cancel_time) {}

FFI_PLUGIN_EXPORT void wajuce_param_cancel_and_hold(int32_t node_id,
                                                    const char *param,
                                                    double time) {}

FFI_PLUGIN_EXPORT float wajuce_param_get(int32_t node_id, const char *param) {
  return 0.0f;
}

// ============================================================================
// Oscillator
// ============================================================================

FFI_PLUGIN_EXPORT void wajuce_osc_set_type(int32_t node_id, int32_t type) {}
FFI_PLUGIN_EXPORT void wajuce_osc_start(int32_t node_id, double when) {}
FFI_PLUGIN_EXPORT void wajuce_osc_stop(int32_t node_id, double when) {}
FFI_PLUGIN_EXPORT void wajuce_osc_set_periodic_wave(int32_t node_id,
                                                    const float *real,
                                                    const float *imag,
                                                    int32_t len,
                                                    int32_t disable_normalization) {}

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

FFI_PLUGIN_EXPORT void
wajuce_buffer_source_start_with_offset(int32_t node_id, double when,
                                       double offset, double duration,
                                       int32_t has_duration) {}

FFI_PLUGIN_EXPORT void wajuce_buffer_source_stop(int32_t node_id, double when) {
}

FFI_PLUGIN_EXPORT void wajuce_buffer_source_set_loop(int32_t node_id,
                                                     int32_t loop) {}

FFI_PLUGIN_EXPORT void
wajuce_buffer_source_set_loop_points(int32_t node_id, double loop_start,
                                     double loop_end) {}

// ============================================================================
// Analyser
// ============================================================================

FFI_PLUGIN_EXPORT void wajuce_analyser_set_fft_size(int32_t node_id,
                                                    int32_t size) {}

FFI_PLUGIN_EXPORT void wajuce_analyser_set_min_decibels(int32_t node_id,
                                                        double value) {}

FFI_PLUGIN_EXPORT void wajuce_analyser_set_max_decibels(int32_t node_id,
                                                        double value) {}

FFI_PLUGIN_EXPORT void
wajuce_analyser_set_smoothing_time_constant(int32_t node_id, double value) {}

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

FFI_PLUGIN_EXPORT void wajuce_biquad_get_frequency_response(
    int32_t node_id, const float *frequency_hz, float *mag_response,
    float *phase_response, int32_t len) {
  if (mag_response)
    memset(mag_response, 0, len * sizeof(float));
  if (phase_response)
    memset(phase_response, 0, len * sizeof(float));
}

FFI_PLUGIN_EXPORT void wajuce_iir_get_frequency_response(
    int32_t node_id, const float *frequency_hz, float *mag_response,
    float *phase_response, int32_t len) {
  if (mag_response)
    memset(mag_response, 0, len * sizeof(float));
  if (phase_response)
    memset(phase_response, 0, len * sizeof(float));
}

FFI_PLUGIN_EXPORT float wajuce_compressor_get_reduction(int32_t node_id) {
  return 0.0f;
}

FFI_PLUGIN_EXPORT void wajuce_panner_set_panning_model(int32_t node_id,
                                                       int32_t model) {}
FFI_PLUGIN_EXPORT void wajuce_panner_set_distance_model(int32_t node_id,
                                                        int32_t model) {}
FFI_PLUGIN_EXPORT void wajuce_panner_set_ref_distance(int32_t node_id,
                                                      double value) {}
FFI_PLUGIN_EXPORT void wajuce_panner_set_max_distance(int32_t node_id,
                                                      double value) {}
FFI_PLUGIN_EXPORT void wajuce_panner_set_rolloff_factor(int32_t node_id,
                                                        double value) {}
FFI_PLUGIN_EXPORT void wajuce_panner_set_cone_inner_angle(int32_t node_id,
                                                          double value) {}
FFI_PLUGIN_EXPORT void wajuce_panner_set_cone_outer_angle(int32_t node_id,
                                                          double value) {}
FFI_PLUGIN_EXPORT void wajuce_panner_set_cone_outer_gain(int32_t node_id,
                                                         double value) {}

// ============================================================================
// WaveShaper
// ============================================================================

FFI_PLUGIN_EXPORT void
wajuce_wave_shaper_set_curve(int32_t node_id, const float *data, int32_t len) {}

FFI_PLUGIN_EXPORT void wajuce_wave_shaper_set_oversample(int32_t node_id,
                                                         int32_t type) {}

FFI_PLUGIN_EXPORT void
wajuce_convolver_set_buffer(int32_t node_id, const float *data, int32_t frames,
                            int32_t channels, int32_t sr, int32_t normalize) {}

FFI_PLUGIN_EXPORT void wajuce_convolver_set_normalize(int32_t node_id,
                                                      int32_t normalize) {}

// ============================================================================
// WorkletBridge
// ============================================================================

FFI_PLUGIN_EXPORT int32_t wajuce_create_worklet_bridge(int32_t ctx_id,
                                                       int32_t num_inputs,
                                                       int32_t num_outputs) {
  return -1;
}

FFI_PLUGIN_EXPORT float *wajuce_worklet_get_buffer_ptr(int32_t ctx_id,
                                                       int32_t bridge_id,
                                                       int32_t direction,
                                                       int32_t channel) {
  return 0;
}

FFI_PLUGIN_EXPORT int32_t wajuce_worklet_get_input_channel_count(
    int32_t ctx_id, int32_t bridge_id) {
  return 0;
}

FFI_PLUGIN_EXPORT int32_t wajuce_worklet_get_output_channel_count(
    int32_t ctx_id, int32_t bridge_id) {
  return 0;
}

FFI_PLUGIN_EXPORT int32_t wajuce_worklet_get_read_pos(int32_t ctx_id,
                                                      int32_t bridge_id,
                                                      int32_t direction,
                                                      int32_t channel) {
  return 0;
}

FFI_PLUGIN_EXPORT int32_t wajuce_worklet_get_write_pos(int32_t ctx_id,
                                                       int32_t bridge_id,
                                                       int32_t direction,
                                                       int32_t channel) {
  return 0;
}

FFI_PLUGIN_EXPORT void wajuce_worklet_set_read_pos(int32_t ctx_id,
                                                   int32_t bridge_id,
                                                   int32_t direction,
                                                   int32_t channel,
                                                   int32_t value) {}

FFI_PLUGIN_EXPORT void wajuce_worklet_set_write_pos(int32_t ctx_id,
                                                    int32_t bridge_id,
                                                    int32_t direction,
                                                    int32_t channel,
                                                    int32_t value) {}

FFI_PLUGIN_EXPORT int32_t wajuce_worklet_get_capacity(int32_t ctx_id,
                                                      int32_t bridge_id) {
  return 0;
}

FFI_PLUGIN_EXPORT void wajuce_worklet_release_bridge(int32_t ctx_id,
                                                     int32_t bridge_id) {}

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

FFI_PLUGIN_EXPORT void
wajuce_midi_set_callback(wajuce_midi_callback_t callback) {}

FFI_PLUGIN_EXPORT void wajuce_midi_dispose() {}

FFI_PLUGIN_EXPORT int32_t wajuce_decode_audio_data(const uint8_t *encoded_data,
                                                   int32_t len, float *out_data,
                                                   int32_t *out_frames,
                                                   int32_t *out_channels,
                                                   int32_t *out_sr) {
  return -1;
}
