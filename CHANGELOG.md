## 0.3.1 - 2026-05-03

* **Web Analyser Fix**: Fixed Web/WASM analyser readback so `getByteTimeDomainData`, `getByteFrequencyData`, `getFloatTimeDomainData`, and `getFloatFrequencyData` return browser-filled typed-array data instead of stale Dart-side buffers.
* **Web I/O Visualizer**: Restored I/O & Rec oscilloscope updates for decoded file playback and microphone analysis paths, independent of monitor on/off state.
* **WebAssembly Compatibility**: Removed invalid runtime type checks from the web worklet message bridge and raised the Dart SDK lower bound to `^3.6.0` for typed-array interop constructors required by the fix.

## 0.3.0 - 2026-05-03

* **Native Runtime Migration**: Replaced the legacy JUCE native runtime with an iPlug2-backed WebAudio render graph and Dart FFI ABI.
* **JUCE Removal**: Removed the old JUCE submodule, JUCE wrapper sources, `WajuceEngine`, `Processors`, and `NodeRegistry` native graph path from the package.
* **iPlug2 Packaging**: Added `native/engine/vendor/iPlug2`, Apple wrapper sources, RtAudio/RtMidi wrapper integration, and iPlug2-oriented CocoaPods/CMake packaging.
* **AudioNode/AudioParam Parity**: Added bounded `AudioNode.connect(...)` validation and native/web `connectParam(WAParam)` support so node outputs can modulate AudioParams.
* **Disconnect Parity**: Added native/web-backed explicit disconnect methods for output-specific, node-route-specific, and AudioParam-specific disconnection.
* **Native Param Rendering**: Added native AudioParam input summing with mono downmix behavior and smoke coverage for node-to-param gain and compressor-threshold modulation.
* **Worklet Parameters**: Added Dart module parameter descriptors and fed `WAWorkletProcessor.process()` parameter blocks from the current backend scalar AudioParam values instead of passing an empty map.
* **decodeAudioData Coverage**: Added an Apple AudioToolbox fallback for system-supported compressed formats such as AAC/MP3, while retaining direct PCM/float WAV/AIFF/AIFC parsing.
* **Native Shared Export Fix**: Forced the static iPlug2-backed engine archive into the shared FFI library so exported `wajuce_*` C ABI symbols are present at runtime.
* **iOS/macOS Timing Validation**: Stabilized the example sequencer machine-voice path with warm voice pooling, audio-time lookahead scheduling, inactive machine voices, and silent delay-branch skipping; verified iOS device playback after the migration.

## 0.2.4

* **Native Timing Hardening**: Aligned native startup with actual device sample-rate/buffer-size, avoided coarse software downsample on near-native mismatches (for example `44.1k` requests on `48k` iOS devices), and added callback budget/xrun health diagnostics for timing investigation.
* **Feedback/Cycle Routing Fixes**: Corrected native cycle handling to validate channels before bridge creation, use actual endpoint channel counts instead of broad 32-channel iteration, and fully remove all matching connections/feedback bridges on disconnect.
* **Worklet Bridge Safety**: Moved native worklet bridge state to shared lifetime-managed storage, added explicit bridge release handshake after isolate-side node removal, and hardened native FFI lookup to use `contextId + bridgeId` with channel-count/capacity introspection.
* **RT-Safe Processing**: Removed audio-thread dynamic buffer growth in critical gain/delay paths, switched automation registry access to non-blocking lock attempts, and tightened ring-buffer access around atomic read/write positions.
* **Context Channel Configuration**: Added explicit `inputChannels` / `outputChannels` handling in `WAContext` while preserving `numberOfChannels` compatibility, so requested I/O topology survives context recreation more predictably.
* **Example Sequencer Diagnostics**: Added sequencer/clock transport instrumentation in the example app for future reproduction of `tick timeout`, worklet clock state changes, and transport stop scenarios without changing library API semantics.
* **Package Metadata Cleanup**: Restored formatter cleanliness in older library files and added a no-op Flutter web plugin registrant so pub.dev platform detection matches the existing web backend support.

## 0.2.3

* **Auto-Dispose (Phase 1)**: Added scheduled-source auto-dispose with last-write-wins `stop()` semantics and idempotent worklet ended-node cleanup path.
* **Owned Cascade (Phase 2)**: Added `connectOwned(...)` for explicit owned-subgraph disposal cascade without touching shared buses.
* **Native Machine Voice Lifecycle (Phase 3)**: Added backend machine-voice group tracking so disposing any member reclaims the full native prewired graph.
* **Diagnostics API**: Added `WAContext.graphStats` with `liveNodeCount`, `feedbackBridgeCount`, and `machineVoiceGroupCount`.
* **Example Migration**: Updated one-shot and voice-local chains in `example/lib/main.dart` to use `connectOwned(...)`.
* **Regression Tests**: Expanded integration coverage for machine-voice lifecycle reclamation and repeated one-shot leak checks.
* **Scheduler Documentation/Example**: Documented `Precise (Timeline)` vs `Live (Low Latency)` policy with `Precise` default guidance, added `Timer.periodic` timing caveat, and updated example tabs to demonstrate the split (Synth Pad/I/O=`Live`, Sequencer=`Precise`).

## 0.2.2

* **Audio Settings UX**: Added explicit split between `Device I/O` (actual hardware format) and `Render target` (requested render format) to prevent sample-rate/bit-depth confusion on iOS.
* **Lo-Fi Render Targets**: Added low-fi render options in the example settings UI (`8000/11025/22050 Hz`, `4/8/12-bit`) alongside standard values.
* **Native Lo-Fi Processing**: Added software sample-rate reduction and bit-crush post-processing so render target changes remain clearly audible even when device hardware stays at 48 kHz.
* **Context Recreate Stability**: Fixed no-sound cases after applying audio settings by forcing tab state/node recreation when the audio context is replaced.
* **Docs/Packaging**: Renamed top-level docs directory to `doc/` for pub layout convention and updated references.

## 0.2.1

* **Documentation Accuracy**: Synchronized README feature/status wording with current implementation details.
* **AudioWorklet Wording**: Clarified native vs web worklet behavior in feature/overview sections.
* **Status Matrix Refresh**: Updated implementation date and expanded coverage notes for context extras and extended node surface.

## 0.2.0

* **Agent Install Automation**: Added cross-platform executable installer and verifier scripts for first-time integration:
  * `tool/install_wajuce.dart`
  * `tool/verify_wajuce.dart`
  * Shared command utility: `tool/_wajuce_cli.dart`
* **Windows-Focused Guardrails**: Added deterministic host/toolchain gating for Windows targets (`windows` desktop and `android` on Windows) via `flutter doctor -v` checks and explicit host compatibility failures.
* **Path Source Reliability**: Added WebAudio native path-source validation and submodule bootstrap logic for local/path dependency flows.
* **Docs Refresh**: Added new-project quick start and deterministic agent-install usage in `README.md`; converted `SKILLS.md` into an orchestration playbook that delegates execution to scripts.

## 0.1.5

* **Interface Coverage Expansion**: Added Web Audio 1.1 surface for `AudioScheduledSourceNode`, `ConstantSourceNode`, `ConvolverNode`, `IIRFilterNode`, `PannerNode`, `MediaElementAudioSourceNode`, and `MediaStreamTrackAudioSourceNode`.
* **Context Extras**: Added `listener`, `baseLatency`, `outputLatency`, `sinkId`, `getOutputTimestamp()`, and minimal `AudioRenderCapacity` wrappers.
* **AudioParam/Node Parity**: Wired `setValueCurveAtTime`, buffer-source advanced start/loop window fields, analyser decibel/smoothing setters, biquad frequency response, and compressor reduction getter paths.
* **Worklet Parity**: Added minimal `AudioParamMap`-style `parameters` exposure on `WAWorkletNode`.
* **Deprecated Policy**: Added minimal compatibility shims for deprecated `ScriptProcessorNode` and `AudioProcessingEvent` only.
* **Backend Alignment**: Synchronized `web`, native, and `stub` backend interfaces for the new API surface, including safe guards for unsupported listener IDs.
* **Documentation**: Updated Web Audio 1.1 interface checklist with implementation/shim status and next parity gaps.

## 0.1.4

* **AudioWorklet Ergonomics**: Added `WAWorkletModules`-based module loading flow and improved example usage so processor/module identifiers are encapsulated behind helper APIs.
* **Sequencer Stability**: Reduced click/tick artifacts by improving parameter update scheduling (`cancelAndHoldAtTime`, warm-up parameter sync, smoother runtime updates).
* **Delay Behavior**: Updated sequencer delay control to keep `DelayNode.delayTime` continuously synchronized (independent of wet bypass), avoiding first-enable jumps.
* **Feedback Loop Fix**: Restored native machine-voice external feedback path (`Delay -> Gain -> Delay`) using a managed one-block feedback bridge in WebAudio native graph.
* **Stereo/IO Fixes**: Corrected machine-voice internal routing to true stereo and improved mono microphone monitoring behavior on iOS.
* **Release Hygiene**: Updated package metadata and publish configuration for cleaner pub.dev validation.

## 0.1.3

* **Maintenance**: Improved pub.dev score by resolving all library and example analysis issues.
* **Package Hygiene**: Optimized package size and scoring by excluding unnecessary WebAudio native vendor assets via `.pubignore`.
* **Consistency**: Standardized backend interfaces and naming conventions (renamed `URL` to `url` in JS interop).
* **Web Sequencer Fix**: Resolved critical issue where Sequencer would not advance on Web by implementing a custom `AudioWorkletProcessor` bridge for accurate timing.
* **Web I/O Fix**: Added full support for `MediaStreamSourceNode` (Microphone input) via `navigator.mediaDevices.getUserMedia`.
* **Cross-Platform Bug Fixes**: Corrected iOS compilation errors and fixed a critical bug where unconnected nodes (like the Clock) were suspended by the browser/OS, halting logic.
* **Architecture**: Refactored `AudioWorklet` system and `RingBuffer` logic to use conditional imports, ensuring a clean compilation path for Web platforms.

## 0.1.1

* **Performance Optimization**: Implemented native batch node creation (`createMachineVoice`) to reduce FFI overhead and thread contention.
* **Lazy Connection**: Voices in the pool now remain disconnected from the master output until actively claimed, reducing background CPU usage.
* **Stability Fixes**: Corrected illegal feedback cycles in WebAudio native's `native render graph` that caused exponential slowdowns.
* **UI Responsiveness**: Refined voice pool replenishment to yield during creation, preventing UI freezes in the Sequencer.
* **Bug Fixes**: Corrected native processor initialization and oscillator startup logic.

## 0.1.0

* Initial release of `wajuce`.
* Web Audio API 1.1 compatible interfaces.
* Native backend using WebAudio native 8 (FFI).
* Web backend using `dart:js_interop`.
* Support for 12 AudioParam automation methods.
* AudioWorklet emulation via High-Priority Dart Isolates.
* Feedback loop support via automatic FeedbackBridge.
