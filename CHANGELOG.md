## 0.1.2

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
