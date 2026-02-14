## 0.2.0

* **Agent Install Automation**: Added cross-platform executable installer and verifier scripts for first-time integration:
  * `tool/install_wajuce.dart`
  * `tool/verify_wajuce.dart`
  * Shared command utility: `tool/_wajuce_cli.dart`
* **Windows-Focused Guardrails**: Added deterministic host/toolchain gating for Windows targets (`windows` desktop and `android` on Windows) via `flutter doctor -v` checks and explicit host compatibility failures.
* **Path Source Reliability**: Added JUCE path-source validation and submodule bootstrap logic for local/path dependency flows.
* **Docs Refresh**: Added new-project quick start and deterministic agent-install usage in `README.md`; converted `SKILLS.md` into an orchestration playbook that delegates execution to scripts.

## 0.1.5

* **Interface Coverage Expansion**: Added Web Audio 1.1 surface for `AudioScheduledSourceNode`, `ConstantSourceNode`, `ConvolverNode`, `IIRFilterNode`, `PannerNode`, `MediaElementAudioSourceNode`, and `MediaStreamTrackAudioSourceNode`.
* **Context Extras**: Added `listener`, `baseLatency`, `outputLatency`, `sinkId`, `getOutputTimestamp()`, and minimal `AudioRenderCapacity` wrappers.
* **AudioParam/Node Parity**: Wired `setValueCurveAtTime`, buffer-source advanced start/loop window fields, analyser decibel/smoothing setters, biquad frequency response, and compressor reduction getter paths.
* **Worklet Parity**: Added minimal `AudioParamMap`-style `parameters` exposure on `WAWorkletNode`.
* **Deprecated Policy**: Added minimal compatibility shims for deprecated `ScriptProcessorNode` and `AudioProcessingEvent` only.
* **Backend Alignment**: Synchronized `web`, `juce`, and `stub` backend interfaces for the new API surface, including safe JUCE no-op guards for unsupported listener IDs.
* **Documentation**: Updated Web Audio 1.1 interface checklist with implementation/shim status and next parity gaps.

## 0.1.4

* **AudioWorklet Ergonomics**: Added `WAWorkletModules`-based module loading flow and improved example usage so processor/module identifiers are encapsulated behind helper APIs.
* **Sequencer Stability**: Reduced click/tick artifacts by improving parameter update scheduling (`cancelAndHoldAtTime`, warm-up parameter sync, smoother runtime updates).
* **Delay Behavior**: Updated sequencer delay control to keep `DelayNode.delayTime` continuously synchronized (independent of wet bypass), avoiding first-enable jumps.
* **Feedback Loop Fix**: Restored native machine-voice external feedback path (`Delay -> Gain -> Delay`) using a managed one-block feedback bridge in JUCE graph.
* **Stereo/IO Fixes**: Corrected machine-voice internal routing to true stereo and improved mono microphone monitoring behavior on iOS.
* **Release Hygiene**: Updated package metadata and publish configuration for cleaner pub.dev validation.

## 0.1.3

* **Maintenance**: Improved pub.dev score by resolving all library and example analysis issues.
* **Package Hygiene**: Optimized package size and scoring by excluding unnecessary JUCE vendor assets via `.pubignore`.
* **Consistency**: Standardized backend interfaces and naming conventions (renamed `URL` to `url` in JS interop).
* **Web Sequencer Fix**: Resolved critical issue where Sequencer would not advance on Web by implementing a custom `AudioWorkletProcessor` bridge for accurate timing.
* **Web I/O Fix**: Added full support for `MediaStreamSourceNode` (Microphone input) via `navigator.mediaDevices.getUserMedia`.
* **Cross-Platform Bug Fixes**: Corrected iOS compilation errors and fixed a critical bug where unconnected nodes (like the Clock) were suspended by the browser/OS, halting logic.
* **Architecture**: Refactored `AudioWorklet` system and `RingBuffer` logic to use conditional imports, ensuring a clean compilation path for Web platforms.

## 0.1.1

* **Performance Optimization**: Implemented native batch node creation (`createMachineVoice`) to reduce FFI overhead and thread contention.
* **Lazy Connection**: Voices in the pool now remain disconnected from the master output until actively claimed, reducing background CPU usage.
* **Stability Fixes**: Corrected illegal feedback cycles in JUCE's `AudioProcessorGraph` that caused exponential slowdowns.
* **UI Responsiveness**: Refined voice pool replenishment to yield during creation, preventing UI freezes in the Sequencer.
* **Bug Fixes**: Corrected native processor initialization and oscillator startup logic.

## 0.1.0

* Initial release of `wajuce`.
* Web Audio API 1.1 compatible interfaces.
* Native backend using JUCE 8 (FFI).
* Web backend using `dart:js_interop`.
* Support for 12 AudioParam automation methods.
* AudioWorklet emulation via High-Priority Dart Isolates.
* Feedback loop support via automatic FeedbackBridge.
