/// wajuce — Web Audio API 1.1 for Flutter
///
/// Cross-platform audio framework using JUCE for native platforms
/// and the browser's Web Audio API for the web.
///
/// ```dart
/// import 'package:wajuce/wajuce.dart';
///
/// final ctx = WAContext();
/// await ctx.resume();
///
/// final osc = ctx.createOscillator();
/// osc.frequency.value = 440;
/// osc.connect(ctx.destination);
/// osc.start();
/// ```
library wajuce;

// Core
export 'src/context.dart';
export 'src/offline_context.dart';
export 'src/audio_param.dart';
export 'src/audio_buffer.dart';

// Nodes — Base
export 'src/nodes/audio_node.dart';
export 'src/nodes/channel_splitter_node.dart';
export 'src/nodes/channel_merger_node.dart';
export 'src/nodes/audio_destination_node.dart';

// Nodes — P1 (Foundation)
export 'src/nodes/gain_node.dart';
export 'src/nodes/oscillator_node.dart';
export 'src/nodes/biquad_filter_node.dart';
export 'src/nodes/stereo_panner_node.dart';
export 'src/nodes/dynamics_compressor_node.dart';
export 'src/nodes/delay_node.dart';
export 'src/nodes/buffer_source_node.dart';
export 'src/nodes/analyser_node.dart';
export 'src/nodes/wave_shaper_node.dart';
export 'src/nodes/media_stream_nodes.dart';
export 'src/nodes/periodic_wave.dart';

// Worklet
export 'src/worklet/wa_worklet.dart';
export 'src/worklet/wa_worklet_module.dart';
export 'src/worklet/wa_worklet_node.dart';
export 'src/worklet/wa_worklet_processor.dart';

// MIDI
export 'src/midi.dart';

// Enums
export 'src/enums.dart';
