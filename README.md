# wajuce

[![Pub](https://img.shields.io/pub/v/wajuce.svg)](https://pub.dev/packages/wajuce)

**JUCE-powered Web Audio API for Flutter.**

`wajuce` provides a Web Audio API 1.1 compatible interface for Flutter and Dart. It allows developers to use familiar Web Audio patterns while delivering high-performance, low-latency audio processing via a native JUCE C++ backend.

---

## 🌟 Key Features

- **Web Audio API Parity**: Mirrors `AudioContext`, `OscillatorNode`, `GainNode`, etc., making it easy to port existing JS audio engines.
- **JUCE Backend**: Leverages the industry-standard JUCE framework for native audio processing on iOS, Android, macOS, and Windows.
- **Pure Web Support**: Automatically falls back to the browser's native Web Audio API on Web platforms via `dart:js_interop`.
- **Zero-Overhead FFI**: Uses Dart FFI for fast communication between Dart and C++ without MethodChannel overhead.
- **AudioWorklet Support**: Emulates the AudioWorklet system using high-priority Dart Isolates.
- **Feedback Loops**: Built-in `FeedbackBridge` automatically handles cyclic connections in the node graph (1-block delay).

---

## 🏗️ Architecture

`wajuce` is built on a multi-backend architecture that ensures code portability across all platforms:

```mermaid
graph TD
    subgraph "Dart API Layer"
        A[WAContext] --> B[WANode Graph]
    end

    subgraph "Platform Backends"
        B -->|Native| C[backend_juce.dart]
        B -->|Web| D[backend_web.dart]
    end

    subgraph "Native Layer (C++/JUCE)"
        C --> E[FFI Bridge]
        E --> F[WajuceEngine]
        F --> G[JUCE AudioProcessorGraph]
    end

    subgraph "Web Layer (JS)"
        D --> H[Browser Web Audio API]
    end
```

---

## 🚀 Current Implementation Status (2026-02-12)

| Feature Group | Status | Component Coverage |
| :--- | :---: | :--- |
| **Context & Graph** | ✅ Done | `WAContext`, `WAOfflineContext`, `connect/disconnect` |
| **Multi-Channel** | ✅ Done | Support up to 32 channels, `ChannelSplitter`, `ChannelMerger` |
| **Core Nodes** | ✅ Done | `Oscillator`, `Gain`, `BiquadFilter`, `Compressor`, `Delay`, `Analyser`, `StereoPanner`, `WaveShaper`, `BufferSource` |
| **AudioParam** | ✅ Done | Full automation (12 methods including `exponentialRampToValueAtTime`) |
| **MIDI API** | ✅ Done | Hardware I/O, device enumeration, SysEx support |
| **AudioWorklet** | ✅ Done | High-priority Isolate + Lock-free Native Ring Buffer Bridge |
| **Web Backend** | ✅ Done | Native passthrough via `js_interop` |
| **Build System** | ✅ Done | iOS, Android, macOS, Windows (CMake-ready) |

---

## ⚡ v0.1.1 Performance & Scalability
The 0.1.1 release introduces significant optimizations for complex node graphs:
- **Native Batch Creation**: Create complex voices (15+ nodes) in a single FFI call, preventing audio thread contention.
- **Lazy Connection**: Voices in the `MachineVoicePool` are kept disconnected until playback, saving substantial CPU.
- **Async Voice Pooling**: Background replenishment of voice pools to ensure glitch-free sequencer tracking.

---

## 🎹 AudioWorklet
Run custom DSP code in a dedicated high-priority Isolate:

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
- `native/engine/`: The JUCE-based C++ audio engine.
- `src/`: C-API headers and stubs for FFI binding.

---

---

## 🤖 AI Skills & Automation

This project includes specialized **AI Skills** to help agents maintain the development environment.

- **JUCE Management (`juce_setup`)**: Automated detection and setup of the JUCE framework.
  - Located at: `.agent/skills/juce_management/SKILL.md`
  - Purpose: Fixes broken dependencies, handles symlinks, and configures submodules.

To use these skills, simply ask your AI agent: *"Help me set up the JUCE environment using the available skills."*

---

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

The native backend links against JUCE. If you distribute products using the
native JUCE runtime, you must also comply with JUCE's license terms:
[JUCE 8 Licence](https://juce.com/legal/juce-8-licence/).
