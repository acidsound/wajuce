/**
 * wajuce.h — C-API for the Wajuce audio engine.
 *
 * This header defines the FFI interface between Dart and the native engine.
 * On native platforms (macOS, iOS, Android, Windows, Linux), these symbols
 * are resolved from the compiled JUCE engine shared library.
 */
#ifndef WAJUCE_H
#define WAJUCE_H

#include <stdint.h>

// Platform export macro
#ifdef _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
// Context lifecycle
// ============================================================================
FFI_PLUGIN_EXPORT int32_t wajuce_context_create(int32_t sample_rate,
                                                int32_t buffer_size,
                                                int32_t input_channels,
                                                int32_t output_channels);
FFI_PLUGIN_EXPORT void wajuce_context_destroy(int32_t ctx_id);
FFI_PLUGIN_EXPORT double wajuce_context_get_time(int32_t ctx_id);
FFI_PLUGIN_EXPORT double wajuce_context_get_sample_rate(int32_t ctx_id);
FFI_PLUGIN_EXPORT int32_t wajuce_context_get_state(int32_t ctx_id);
FFI_PLUGIN_EXPORT void wajuce_context_resume(int32_t ctx_id);
FFI_PLUGIN_EXPORT void wajuce_context_suspend(int32_t ctx_id);
FFI_PLUGIN_EXPORT void wajuce_context_close(int32_t ctx_id);
FFI_PLUGIN_EXPORT int32_t wajuce_context_get_destination_id(int32_t ctx_id);

// ============================================================================
// Node factory — each returns a node ID
// ============================================================================
FFI_PLUGIN_EXPORT int32_t wajuce_create_gain(int32_t ctx_id);
FFI_PLUGIN_EXPORT int32_t wajuce_create_oscillator(int32_t ctx_id);
FFI_PLUGIN_EXPORT int32_t wajuce_create_biquad_filter(int32_t ctx_id);
FFI_PLUGIN_EXPORT int32_t wajuce_create_compressor(int32_t ctx_id);
FFI_PLUGIN_EXPORT int32_t wajuce_create_delay(int32_t ctx_id, float max_delay);
FFI_PLUGIN_EXPORT int32_t wajuce_create_buffer_source(int32_t ctx_id);
FFI_PLUGIN_EXPORT int32_t wajuce_create_analyser(int32_t ctx_id);
FFI_PLUGIN_EXPORT int32_t wajuce_create_stereo_panner(int32_t ctx_id);
FFI_PLUGIN_EXPORT int32_t wajuce_create_wave_shaper(int32_t ctx_id);

// Batch creation for Machine Voice
// result_ids must be an int32_t array of size 7
FFI_PLUGIN_EXPORT void wajuce_create_machine_voice(int32_t ctx_id,
                                                   int32_t *result_ids);

FFI_PLUGIN_EXPORT void wajuce_remove_node(int32_t ctx_id, int32_t node_id);
FFI_PLUGIN_EXPORT int32_t wajuce_create_media_stream_source(int32_t ctx_id);
FFI_PLUGIN_EXPORT int32_t
wajuce_create_media_stream_destination(int32_t ctx_id);
FFI_PLUGIN_EXPORT int32_t wajuce_create_channel_splitter(int32_t ctx_id,
                                                         int32_t outputs);
FFI_PLUGIN_EXPORT int32_t wajuce_create_channel_merger(int32_t ctx_id,
                                                       int32_t inputs);

// ============================================================================
// Graph topology
// ============================================================================
FFI_PLUGIN_EXPORT void wajuce_connect(int32_t ctx_id, int32_t src_id,
                                      int32_t dst_id, int32_t output,
                                      int32_t input);
FFI_PLUGIN_EXPORT void wajuce_disconnect(int32_t ctx_id, int32_t src_id,
                                         int32_t dst_id);
FFI_PLUGIN_EXPORT void wajuce_disconnect_all(int32_t ctx_id, int32_t src_id);

// ============================================================================
// AudioParam automation
// ============================================================================
FFI_PLUGIN_EXPORT void wajuce_param_set(int32_t node_id, const char *param,
                                        float value);
FFI_PLUGIN_EXPORT void wajuce_param_set_at_time(int32_t node_id,
                                                const char *param, float value,
                                                double time);
FFI_PLUGIN_EXPORT void wajuce_param_linear_ramp(int32_t node_id,
                                                const char *param, float value,
                                                double end_time);
FFI_PLUGIN_EXPORT void wajuce_param_exp_ramp(int32_t node_id, const char *param,
                                             float value, double end_time);
FFI_PLUGIN_EXPORT void wajuce_param_set_target(int32_t node_id,
                                               const char *param, float target,
                                               double start_time, float tc);
FFI_PLUGIN_EXPORT void wajuce_param_cancel(int32_t node_id, const char *param,
                                           double cancel_time);

// ============================================================================
// Oscillator
// ============================================================================
FFI_PLUGIN_EXPORT void wajuce_osc_set_type(int32_t node_id, int32_t type);
FFI_PLUGIN_EXPORT void wajuce_osc_start(int32_t node_id, double when);
FFI_PLUGIN_EXPORT void wajuce_osc_stop(int32_t node_id, double when);
FFI_PLUGIN_EXPORT void wajuce_osc_set_periodic_wave(int32_t node_id,
                                                    const float *real,
                                                    const float *imag,
                                                    int32_t len);

// ============================================================================
// BiquadFilter
// ============================================================================
FFI_PLUGIN_EXPORT void wajuce_filter_set_type(int32_t node_id, int32_t type);

// ============================================================================
// BufferSource
// ============================================================================
FFI_PLUGIN_EXPORT void
wajuce_buffer_source_set_buffer(int32_t node_id, const float *data,
                                int32_t frames, int32_t channels, int32_t sr);
FFI_PLUGIN_EXPORT void wajuce_buffer_source_start(int32_t node_id, double when);
FFI_PLUGIN_EXPORT void wajuce_buffer_source_stop(int32_t node_id, double when);
FFI_PLUGIN_EXPORT void wajuce_buffer_source_set_loop(int32_t node_id,
                                                     int32_t loop);

// ============================================================================
// Analyser
// ============================================================================
FFI_PLUGIN_EXPORT void wajuce_analyser_set_fft_size(int32_t node_id,
                                                    int32_t size);
FFI_PLUGIN_EXPORT void
wajuce_analyser_get_byte_freq(int32_t node_id, uint8_t *data, int32_t len);
FFI_PLUGIN_EXPORT void
wajuce_analyser_get_byte_time(int32_t node_id, uint8_t *data, int32_t len);
FFI_PLUGIN_EXPORT void wajuce_analyser_get_float_freq(int32_t node_id,
                                                      float *data, int32_t len);
FFI_PLUGIN_EXPORT void wajuce_analyser_get_float_time(int32_t node_id,
                                                      float *data, int32_t len);

// ============================================================================
// WaveShaper
// ============================================================================
FFI_PLUGIN_EXPORT void
wajuce_wave_shaper_set_curve(int32_t node_id, const float *data, int32_t len);
FFI_PLUGIN_EXPORT void wajuce_wave_shaper_set_oversample(int32_t node_id,
                                                         int32_t type);

// ============================================================================
// WorkletBridge (Phase 8)
// ============================================================================
FFI_PLUGIN_EXPORT int32_t wajuce_create_worklet_bridge(int32_t ctx_id,
                                                       int32_t num_inputs,
                                                       int32_t num_outputs);
// direction: 0 = To-Isolate, 1 = From-Isolate
FFI_PLUGIN_EXPORT float *wajuce_worklet_get_buffer_ptr(int32_t bridge_id,
                                                       int32_t direction,
                                                       int32_t channel);
FFI_PLUGIN_EXPORT int32_t *wajuce_worklet_get_read_pos_ptr(int32_t bridge_id,
                                                           int32_t direction,
                                                           int32_t channel);
FFI_PLUGIN_EXPORT int32_t *wajuce_worklet_get_write_pos_ptr(int32_t bridge_id,
                                                            int32_t direction,
                                                            int32_t channel);
FFI_PLUGIN_EXPORT int32_t wajuce_worklet_get_capacity(int32_t bridge_id);

// ============================================================================
// MIDI
// ============================================================================
FFI_PLUGIN_EXPORT int32_t wajuce_midi_get_port_count(int32_t type);
FFI_PLUGIN_EXPORT void wajuce_midi_get_port_name(int32_t type, int32_t index,
                                                 char *buffer, int32_t max_len);
FFI_PLUGIN_EXPORT void wajuce_midi_port_open(int32_t type, int32_t index);
FFI_PLUGIN_EXPORT void wajuce_midi_port_close(int32_t type, int32_t index);
FFI_PLUGIN_EXPORT void wajuce_midi_output_send(int32_t index,
                                               const uint8_t *data, int32_t len,
                                               double timestamp);

typedef void (*wajuce_midi_callback_t)(int32_t port_index, const uint8_t *data,
                                       int32_t len, double timestamp);
FFI_PLUGIN_EXPORT void
wajuce_midi_set_callback(wajuce_midi_callback_t callback);

FFI_PLUGIN_EXPORT void wajuce_midi_dispose();

// ============================================================================
// Audio Decoding
// ============================================================================
FFI_PLUGIN_EXPORT int32_t wajuce_decode_audio_data(const uint8_t *encoded_data,
                                                   int32_t len, float *out_data,
                                                   int32_t *out_frames,
                                                   int32_t *out_channels,
                                                   int32_t *out_sr);

#ifdef __cplusplus
}
#endif

#endif // WAJUCE_H
