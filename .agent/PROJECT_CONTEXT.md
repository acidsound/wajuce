# wajuce — JUCE-powered Web Audio API for Flutter

## Overview
Flutter plugin providing Web Audio API 1.1-compatible interfaces. 
- **Native** (iOS/Android/macOS/Windows): JUCE C++ engine via FFI
- **Web**: Browser Web Audio API via `dart:js_interop`

## Current Implementation Status (2026-02-11)

### ✅ COMPLETED
| Phase | Content |
|:---:|:---|
| **1** | Foundation: Dart API (27 Dart files), 9 node types, WAParam (12 automation methods), WABuffer, WAContext/WAOfflineContext, 3-backend conditional import, C-API header (32+ functions), C stub |
| **2** | JUCE Engine: 6 AudioProcessors (`Processors.h`), NodeRegistry, ParamAutomation timeline, WajuceEngine with AudioProcessorGraph, full C bridge (`WajuceEngine.cpp`) |
| **3** | AudioWorklet: Dart Isolate worker, SPSC RingBuffer, WAWorkletNode with MessagePort, WAContext.audioWorklet + createWorkletNode() |
| **5** | MIDI API: WAMidi/WAMidiInput/WAMidiOutput (Dart), SysEx helper, device enumeration, hot-plug streams, C-API MIDI functions in header |
| **8** | Polish: `dart analyze` → **0 issues**, CMake dual-mode (JUCE/stub) |

### ❌ NOT YET IMPLEMENTED
| Phase | Content |
|:---:|:---|
| **4** | Buffer/I/O: `decodeAudioData()` native impl, BufferSource data transfer, MediaStream (mic/recording) |
| **5** partial | MIDI C++ native impl (JUCE MidiInput/MidiOutput bridge in WajuceEngine.cpp) |
| **6** | Web backend: `backend_web.dart` has stubs only — needs actual `dart:js_interop` calls |
| **7** | Integration examples: acidBros TB303, ddxx7 DX7, uss44 VoiceProcessor porting |

### ⚠️ NOT YET BUILD-TESTED
- Native build (`flutter build macos/ios/android`) has NOT been tested
- JUCE vendor symlink comes from `acidBros_flutter/native/juce_engine/vendor/JUCE`

## File Inventory

### Dart (lib/) — 27 files
```
wajuce.dart                          # Public exports
src/context.dart                     # WAContext (AudioContext equivalent)
src/offline_context.dart             # WAOfflineContext
src/audio_param.dart                 # WAParam (12 automation methods)
src/audio_buffer.dart                # WABuffer
src/enums.dart                       # All Web Audio enums
src/midi.dart                        # WAMidi, WAMidiInput, WAMidiOutput
src/nodes/audio_node.dart            # WANode base class
src/nodes/audio_destination_node.dart
src/nodes/gain_node.dart
src/nodes/oscillator_node.dart
src/nodes/biquad_filter_node.dart
src/nodes/dynamics_compressor_node.dart
src/nodes/delay_node.dart
src/nodes/buffer_source_node.dart
src/nodes/analyser_node.dart
src/nodes/stereo_panner_node.dart
src/nodes/wave_shaper_node.dart
src/worklet/wa_worklet.dart          # AudioWorklet manager
src/worklet/wa_worklet_node.dart     # AudioWorkletNode
src/worklet/wa_worklet_processor.dart # AudioWorkletProcessor base
src/worklet/audio_isolate.dart       # Dart Isolate worker
src/worklet/ring_buffer.dart         # SPSC lock-free buffer
src/backend/backend.dart             # Conditional import switch
src/backend/backend_juce.dart        # FFI → JUCE (408 lines)
src/backend/backend_web.dart         # js_interop stubs (214 lines)
src/backend/backend_stub.dart        # Analyzer stubs (175 lines)
```

### C/C++ Native — 9 files
```
src/wajuce.h                         # C-API header (32+ FFI functions)
src/wajuce.c                         # C stub implementation
src/CMakeLists.txt                   # Dual mode: JUCE or WAJUCE_STUB_ONLY
native/engine/CMakeLists.txt         # JUCE engine build
native/engine/Source/WajuceEngine.h   # Engine header
native/engine/Source/WajuceEngine.cpp # Engine + C bridge impl
native/engine/Source/Processors.h     # 6 AudioProcessor impls
native/engine/Source/NodeRegistry.h   # ID→Processor mapping
native/engine/Source/ParamAutomation.h # Param scheduling timeline
```

## Key Design Decisions
- **FFI over MethodChannel** for zero-overhead audio calls
- **AudioProcessorGraph** for node routing (matches Web Audio spec)
- **Dart Isolate** for AudioWorklet (keeps processor code in Dart)
- **3-backend conditional import**: `dart.library.ffi` → JUCE, `dart.library.js_interop` → Web Audio, fallback → stub
- **JUCE vendor symlink** from `acidBros_flutter` to share framework
- **WAJUCE_STUB_ONLY** CMake for building without JUCE
- **Automatic Cyclic Connections (FeedbackBridge)**: Detects cycles during `connect()` and automatically inserts a `FeedbackSender`/`FeedbackReceiver` pair with a shared buffer (1-block delay) to allow feedback loops without violating JUCE's GraphQL DAG constraints.

## Reference Documents
- Architecture spec: `.agent/wajuce_architect.md`
- Implementation plan: see conversation artifacts
