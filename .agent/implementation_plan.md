# wajuce iPlug2 Native Runtime Implementation Plan

## Goal

Implement Web Audio API 1.1-style behavior in Dart/Flutter with:

- Browser Web Audio passthrough on web.
- Native iPlug2-backed C++ runtime over Dart FFI on native targets.

The native runtime should be designed as a WebAudio renderer first, not as a
framework graph migration.

## Phases

1. **Runtime Swap**
   - Vendor iPlug2 as `native/engine/vendor/iPlug2`.
   - Build `WAIPlugEngine` from `src/CMakeLists.txt`.
   - Keep `src/wajuce.h` ABI stable.

2. **Core Render Graph**
   - Context lifecycle and deterministic block render.
   - `connect`, `disconnect`, `disconnectAll`.
   - Destination, Gain, Oscillator, BufferSource, Delay, StereoPanner.
   - One-block bounded feedback behavior.

3. **AudioParam**
   - `value`, `setValueAtTime`, linear/exponential ramp, target, cancel,
     cancel-and-hold.
   - Add native curve scheduling if Dart-side point expansion is not accurate
     enough.

4. **Node Parity**
   - Biquad all 8 modes.
   - DynamicsCompressor.
   - Analyser byte/float time/frequency data.
   - WaveShaper and oversampling policy.
   - ChannelSplitter/ChannelMerger.
   - ConstantSource, IIRFilter, Convolver, Panner.

5. **Worklet/MIDI/I/O**
   - Worklet ring-buffer lifetime and teardown tests.
   - MIDI enumeration/input/output via iPlug2 dependency-tree RTMidi where
     available.
   - Desktop realtime output via iPlug2 dependency-tree RtAudio.
   - Platform-specific mobile realtime drivers as a follow-up if RtAudio is not
     suitable for the mobile host.

6. **Verification**
   - Native C++ block-render tests through `wajuce_context_render`.
   - Dart tests for API behavior and backend consistency.
   - Browser comparison fixtures for reference signals where feasible.
   - Flutter example smoke tests after deterministic render tests pass.

## Test Matrix

Each WebAudio node should have:

- construction/defaults test
- connection/channel routing test
- parameter automation test for exposed params
- rendered-signal invariant test
- teardown/disconnect test

High-risk nodes require numeric comparison fixtures:

- `OscillatorNode`
- `AudioBufferSourceNode`
- `GainNode`
- `DelayNode`
- `BiquadFilterNode`
- `StereoPannerNode`
- `WaveShaperNode`
- `AudioWorkletNode`
