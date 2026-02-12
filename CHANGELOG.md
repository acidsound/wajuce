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
