# wajuce

[![Pub](https://img.shields.io/pub/v/wajuce.svg)](https://pub.dev/packages/wajuce)

**iPlug2-backed Web Audio API for Flutter.**

`wajuce` provides a Web Audio API 1.1 compatible interface for Flutter and Dart. It allows developers to use familiar Web Audio patterns while delivering high-performance, low-latency audio processing via a native iPlug2-backed C++ runtime.

---

## 🌟 Key Features

- **Web Audio API Parity**: Mirrors `AudioContext`, `OscillatorNode`, `GainNode`, etc., making it easy to port existing JS audio engines.
- **iPlug2 Native Runtime**: Uses an iPlug2-backed native C++ runtime for desktop/mobile FFI builds.
- **Pure Web Support**: Automatically falls back to the browser's native Web Audio API on Web platforms via `dart:js_interop`.
- **Zero-Overhead FFI**: Uses Dart FFI for fast communication between Dart and C++ without MethodChannel overhead.
- **AudioWorklet Support**: Native uses high-priority Dart Isolates; Web uses browser AudioWorklet via `dart:js_interop`.
- **Feedback Loops**: Built-in `FeedbackBridge` automatically handles cyclic connections in the node graph (1-block delay).
- **Auto-Dispose Lifecycle**: Source nodes auto-dispose on `stop()`/natural end, and `connectOwned(...)` enables explicit owned-subgraph cascade cleanup.
- **Graph Diagnostics**: `WAContext.graphStats` exposes backend live-node/feedback-bridge/machine-voice-group counters for leak checks.
- **Native Stability Hardening**: Native backend now favors actual device format on iOS sample-rate mismatches, hardens worklet bridge teardown/routing, and exposes better callback/xrun diagnostics during timing investigations.
- **Scheduler Policy (Example)**: Example app documents and demonstrates `Precise (Timeline)` vs `Live (Low Latency)` scheduling modes without changing Web Audio API semantics.
- **Lo-Fi Render Targets (Example)**: Example app settings support low sample-rate/bit-depth render targets (`8k/11.025k/22.05k`, `4/8/12-bit`) with clear `Device I/O` vs `Render target` separation.

---

## ⏱️ Scheduler Modes Guide

`wajuce` keeps Web Audio API behavior intact, but application-level schedulers can use different timing policies depending on workload.

| Mode | Recommended Use | Timing Goal |
| :--- | :--- | :--- |
| **Precise (Timeline)** | step sequencers, transport playback, offline-like deterministic playback | stable first-hit/automation timing with larger lookahead |
| **Live (Low Latency)** | realtime MIDI performance, live monitor/effect chains | minimum interaction latency with small lookahead |

Recommended default:
- Use `Precise` unless the path is explicitly realtime.
- Use `Live` only for monitor/play-through/performance paths.
- In app code, default scheduler helpers to `Precise` and override only realtime paths.

Example app policy:
- **Synth Pad tab** runs in `Live (Low Latency)` mode.
- **Sequencer tab** runs in `Precise (Timeline)` mode.
- **I/O & Rec tab** runs in `Live (Low Latency)` mode.

This is a scheduler-layer policy choice, not a change to `AudioContext`/`AudioParam` semantics.

`Timer.periodic` guidance:
- Do **not** use `Timer.periodic` as the source of truth for note-on/off or parameter automation timing.
- Use audio-thread/worklet clock timestamps (`contextTime`, render-quantum ticks) for event scheduling.
- Keep `Timer.periodic` for UI refresh/visualization only (meters, waveform paint, status polling).

---

## 🚀 Quick Start (New Flutter App)

```bash
flutter create my_audio_app
cd my_audio_app
flutter pub add wajuce
flutter pub get
```

Use it in code:

```dart
import 'package:wajuce/wajuce.dart';

Future<void> startAudio() async {
  final ctx = WAContext();
  await ctx.resume();

  final osc = ctx.createOscillator();
  final gain = ctx.createGain();
  gain.gain.value = 0.1;

  osc.connect(gain);
  gain.connect(ctx.destination);
  osc.start();
}
```

### Windows Notes

- Building **Android** on Windows requires Android SDK/NDK/CMake and accepted licenses.
- Building a **Windows executable** requires Visual Studio with Desktop C++ workload.

---

## 🤖 Deterministic Agent Install (Cross-Platform)

From this repository root, run installer scripts against your app path:

macOS/Linux:

```bash
dart run tool/install_wajuce.dart --app-root /absolute/path/to/my_audio_app --source pub --target android
dart run tool/verify_wajuce.dart --app-root /absolute/path/to/my_audio_app --target android
```

Windows (PowerShell):

```powershell
dart run tool/install_wajuce.dart --app-root C:\work\my_audio_app --source pub --target windows
dart run tool/verify_wajuce.dart --app-root C:\work\my_audio_app --target windows
```

Path source install (local plugin checkout):

```bash
dart run tool/install_wajuce.dart --app-root /absolute/path/to/my_audio_app --source path --wajuce-path /absolute/path/to/wajuce --target web
dart run tool/verify_wajuce.dart --app-root /absolute/path/to/my_audio_app --source path --wajuce-path /absolute/path/to/wajuce --target web
```

---

## 🎬 Tutorial Capture Automation (iOS Simulator)

For reproducible screen + audio capture and LRC timeline generation, see:

- `doc/ios_sim_tutorial_capture.md`
- `tool/tutorial_capture/capture_ios_demo.sh`
- `tool/tutorial_capture/sync_and_mux.sh`
- `tool/tutorial_capture/generate_lrc.sh`

---

## 🏗️ Architecture

`wajuce` is built on a multi-backend architecture that ensures code portability across all platforms:

```mermaid
graph TD
    subgraph "Dart API Layer"
        A[WAContext] --> B[WANode Graph]
    end

    subgraph "Platform Backends"
        B -->|Native| C[backend_native.dart]
        B -->|Web| D[backend_web.dart]
    end

    subgraph "Native Layer (C++/iPlug2)"
        C --> E[FFI Bridge]
        E --> F[WAIPlugEngine]
        F --> G[WebAudio Render Graph]
    end

    subgraph "Web Layer (JS)"
        D --> H[Browser Web Audio API]
    end
```

---

## 🚀 Current Implementation Status (2026-05-03)

| Feature Group | Status | Component Coverage |
| :--- | :---: | :--- |
| **Context & Graph** | ✅ Done | `WAContext`, `WAOfflineContext`, bounded node `connect/disconnect`, `connectParam(WAParam)`, explicit output/param disconnect |
| **Context Extras** | ✅ Done | `listener`, `baseLatency`, `outputLatency`, `sinkId`, `getOutputTimestamp()`, `renderCapacity` (minimal wrapper), `graphStats` |
| **Multi-Channel** | ✅ Done | Support up to 32 channels, `ChannelSplitter`, `ChannelMerger` |
| **Core Nodes** | ✅ Done | `Oscillator`, `Gain`, `BiquadFilter`, `Compressor`, `Delay`, `Analyser`, `StereoPanner`, `WaveShaper`, `BufferSource` |
| **Extended Nodes** | ✅ Native-backed | `ConstantSource`, `Convolver`, `IIRFilter`, `Panner`, media stream sources, plus web-backed media element/track sources |
| **AudioParam** | ✅ Done | Full automation (12 methods including `exponentialRampToValueAtTime`) plus native/web audio-rate node-to-param modulation |
| **Deprecated Compatibility** | ✅ Shim | Minimal compatibility for deprecated `ScriptProcessorNode`/`AudioProcessingEvent` |
| **MIDI API** | ✅ Done | Hardware I/O, device enumeration, SysEx support |
| **AudioWorklet** | ✅ Done | Native isolate bridge + Web AudioWorklet passthrough/module loading flow, with Dart processor parameter blocks |
| **Web Backend** | ✅ Done | Browser Web Audio passthrough via `js_interop` (pub.dev platform badge may not list Web due plugin metadata) |
| **Build System** | ✅ Done | iOS, Android, macOS, Windows native backends + Web backend path |

---

## ⚡ v0.1.1 Performance & Scalability
The 0.1.1 release introduces significant optimizations for complex node graphs:
- **Native Batch Creation**: Create complex voices (15+ nodes) in a single FFI call, preventing audio thread contention.
- **Lazy Connection**: Voices in the `MachineVoicePool` are kept disconnected until playback, saving substantial CPU.
- **Async Voice Pooling**: Background replenishment of voice pools to ensure glitch-free sequencer tracking.

---

## 🎹 AudioWorklet
Run custom DSP code with a unified module flow (native isolate bridge, Web AudioWorklet):

```dart
// 1. Define processor
class DX7Processor extends WAWorkletProcessor {
  DX7Processor() : super(name: 'dx7');

  @override
  bool process(inputs, outputs, params) {
    // DSP code here...
    return true;
  }
}

// 2. Register & Run
WAWorkletModules.define('dx7', (registrar) {
  registrar.registerProcessor('dx7', () => DX7Processor());
});
await ctx.audioWorklet.addModule('dx7');
final node = ctx.createWorkletNode('dx7');
node.connect(ctx.destination);
```

---

## 💻 Usage Example

The API is designed to be almost identical to the standard Web Audio API:

```dart
// 1. Initialize context
final ctx = WAContext();
await ctx.resume();

// 2. Create nodes
final osc = ctx.createOscillator();
final filter = ctx.createBiquadFilter();
final gain = ctx.createGain();

// 3. Configure and Automate
osc.type = WAOscillatorType.sawtooth;
filter.frequency.setValueAtTime(440, ctx.currentTime);
filter.frequency.exponentialRampToValueAtTime(2000, ctx.currentTime + 2.0);

// 4. Connect graph
osc.connect(filter);
filter.connect(gain);
gain.connect(ctx.destination);

// 5. Start
osc.start();
```

---

## 🛠️ Project Structure

- `lib/src/`: Dart API implementation and backend switching logic.
- `lib/src/backend/`: Platform-specific implementation (FFI vs JS).
- `native/engine/`: The iPlug2-backed C++ WebAudio runtime.
- `src/`: C-API headers and stubs for FFI binding.

---

## 🤖 AI Skills & Automation

This project includes specialized automation to help agents maintain the development environment.

- **Native runtime setup**: `tool/install_wajuce.dart` and `tool/verify_wajuce.dart` validate local/path dependency checkouts and initialize submodules when needed.
- **Install scripts**:
  - `tool/install_wajuce.dart`
  - `tool/verify_wajuce.dart`
  - Purpose: deterministic first-time installation and validation for macOS/Linux/Windows.

To use these assets, ask your AI agent:
- "Use `SKILLS.md` and run `tool/install_wajuce.dart` for this app."
- "Then run `tool/verify_wajuce.dart` and report pass/fail checks."

---

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

The native backend uses iPlug2 plus its RtAudio/RtMidi dependency path. If you
redistribute native builds, include and comply with the relevant notices under
`native/engine/vendor/iPlug2/LICENSE.txt` and the dependency licenses referenced
there.
