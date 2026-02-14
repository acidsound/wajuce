# Web Audio 1.1 Interface Coverage Checklist

- Updated: 2026-02-14
- Spec source: https://www.w3.org/TR/webaudio-1.1/
- Scope: interface-level parity check for `wajuce` public Dart API and backend wiring.

## Legend

- `IMPLEMENTED`: Interface exists and core API surface is present.
- `PARTIAL`: Interface exists but important members/behavior are missing.
- `MISSING`: No corresponding public API in `wajuce`.

## How This Was Built

- Spec interface list was taken from the W3C Web Audio 1.1 IDL index.
- Local implementation was checked against:
  - `lib/src/context.dart`
  - `lib/src/offline_context.dart`
  - `lib/src/audio_param.dart`
  - `lib/src/nodes/*.dart`
  - `lib/src/worklet/*.dart`
  - `lib/src/backend/backend_juce.dart`
  - `lib/src/backend/backend_web.dart`

## 1) Spec Interface TOC (IDL order)

- [ ] 1.1 BaseAudioContext
- [ ] 1.2 AudioContext
- [ ] 1.2.7 AudioSinkInfo
- [ ] 1.2.9 AudioRenderCapacity
- [ ] 1.2.11 AudioRenderCapacityEvent
- [ ] 1.3 OfflineAudioContext
- [ ] 1.3.5 OfflineAudioCompletionEvent
- [ ] 1.4 AudioBuffer
- [ ] 1.5 AudioNode
- [ ] 1.6 AudioParam
- [ ] 1.7 AudioScheduledSourceNode
- [ ] 1.8 AnalyserNode
- [ ] 1.9 AudioBufferSourceNode
- [ ] 1.10 AudioDestinationNode
- [ ] 1.11 AudioListener
- [ ] 1.12 AudioProcessingEvent (deprecated)
- [ ] 1.13 BiquadFilterNode
- [ ] 1.14 ChannelMergerNode
- [ ] 1.15 ChannelSplitterNode
- [ ] 1.16 ConstantSourceNode
- [ ] 1.17 ConvolverNode
- [ ] 1.18 DelayNode
- [ ] 1.19 DynamicsCompressorNode
- [ ] 1.20 GainNode
- [ ] 1.21 IIRFilterNode
- [ ] 1.22 MediaElementAudioSourceNode
- [ ] 1.23 MediaStreamAudioDestinationNode
- [ ] 1.24 MediaStreamAudioSourceNode
- [ ] 1.25 MediaStreamTrackAudioSourceNode
- [ ] 1.26 OscillatorNode
- [ ] 1.27 PannerNode
- [ ] 1.28 PeriodicWave
- [ ] 1.29 ScriptProcessorNode (deprecated)
- [ ] 1.30 StereoPannerNode
- [ ] 1.31 WaveShaperNode
- [ ] 1.32 AudioWorklet
- [ ] 1.32.3 AudioWorkletGlobalScope
- [ ] 1.32.4 AudioWorkletNode
- [ ] 1.32.4.x AudioParamMap
- [ ] 1.32.5 AudioWorkletProcessor

## 2) Coverage Matrix

| Spec | Interface | wajuce mapping | Status | Notes |
| --- | --- | --- | --- | --- |
| 1.1 | BaseAudioContext | `WAContext` | PARTIAL | Missing several factory methods and attributes (`listener`, etc). |
| 1.2 | AudioContext | `WAContext` | PARTIAL | `resume/suspend/close/state/currentTime` present; `baseLatency/outputLatency/sinkId/getOutputTimestamp/renderCapacity` missing. |
| 1.2.7 | AudioSinkInfo | - | MISSING | No equivalent interface. |
| 1.2.9 | AudioRenderCapacity | - | MISSING | No equivalent interface. |
| 1.2.11 | AudioRenderCapacityEvent | - | MISSING | No equivalent interface. |
| 1.3 | OfflineAudioContext | `WAOfflineContext` | PARTIAL | `startRendering()` is not implemented (`UnimplementedError`). |
| 1.3.5 | OfflineAudioCompletionEvent | - | MISSING | No equivalent interface/event. |
| 1.4 | AudioBuffer | `WABuffer` | IMPLEMENTED | Core attributes and `copyToChannel/copyFromChannel` exist. |
| 1.5 | AudioNode | `WANode` | PARTIAL | Basic connect/disconnect exists, but full overload set and AudioParam destination connect are missing. |
| 1.6 | AudioParam | `WAParam` | PARTIAL | Most automation methods exist; `setValueCurveAtTime()` TODO in backend path. |
| 1.7 | AudioScheduledSourceNode | (implicit in source nodes) | PARTIAL | No shared base type; `start/stop` behavior exists on concrete nodes. |
| 1.8 | AnalyserNode | `WAAnalyserNode` | PARTIAL | FFT/data methods exist; `minDecibels/maxDecibels/smoothingTimeConstant` are not fully backend-wired. |
| 1.9 | AudioBufferSourceNode | `WABufferSourceNode` | PARTIAL | Core playback exists; full `start(when, offset, duration)` semantics and loop fields parity are incomplete. |
| 1.10 | AudioDestinationNode | `WADestinationNode` | PARTIAL | Basic destination exists; `maxChannelCount` is static in current API. |
| 1.11 | AudioListener | - | MISSING | No listener interface or 3D listener params. |
| 1.12 | AudioProcessingEvent (deprecated) | - | MISSING | Deprecated in spec; not exposed. |
| 1.13 | BiquadFilterNode | `WABiquadFilterNode` | PARTIAL | Main params/type exist; `getFrequencyResponse()` is TODO. |
| 1.14 | ChannelMergerNode | `WAChannelMergerNode` | IMPLEMENTED | Core constructor behavior present. |
| 1.15 | ChannelSplitterNode | `WAChannelSplitterNode` | IMPLEMENTED | Core constructor behavior present. |
| 1.16 | ConstantSourceNode | - | MISSING | No constant source node API. |
| 1.17 | ConvolverNode | - | MISSING | No convolver node API. |
| 1.18 | DelayNode | `WADelayNode` | IMPLEMENTED | `delayTime` exists; note extra non-spec `feedback` param is added. |
| 1.19 | DynamicsCompressorNode | `WADynamicsCompressorNode` | PARTIAL | Params exist, but `reduction` is currently fixed value in Dart layer. |
| 1.20 | GainNode | `WAGainNode` | IMPLEMENTED | Core interface is present. |
| 1.21 | IIRFilterNode | - | MISSING | No IIR filter node API. |
| 1.22 | MediaElementAudioSourceNode | - | MISSING | No media element source API. |
| 1.23 | MediaStreamAudioDestinationNode | `WAMediaStreamDestNode` | PARTIAL | Node exists, but spec `stream` property is not exposed on Dart class. |
| 1.24 | MediaStreamAudioSourceNode | `WAMediaStreamSourceNode` | PARTIAL | Node exists, but spec `mediaStream` property is not exposed on Dart class. |
| 1.25 | MediaStreamTrackAudioSourceNode | - | MISSING | No track-source node API. |
| 1.26 | OscillatorNode | `WAOscillatorNode` | PARTIAL | Main params/type/start/stop exist; full scheduled-source event parity is incomplete. |
| 1.27 | PannerNode | - | MISSING | No 3D panner node API. |
| 1.28 | PeriodicWave | `WAPeriodicWave` | PARTIAL | Type exists and is usable via oscillator; full option/constraint parity is incomplete. |
| 1.29 | ScriptProcessorNode (deprecated) | - | MISSING | Not exposed in public API (web backend has internal interop only). |
| 1.30 | StereoPannerNode | `WAStereoPannerNode` | IMPLEMENTED | Core `pan` param and node behavior present. |
| 1.31 | WaveShaperNode | `WAWaveShaperNode` | IMPLEMENTED | `curve` and `oversample` are exposed. |
| 1.32 | AudioWorklet | `WAWorklet` | PARTIAL | `addModule` + processor registration are present; full browser parity is not complete. |
| 1.32.3 | AudioWorkletGlobalScope | (emulated) | PARTIAL | Worklet execution environment exists via isolate/proxy model, not a spec-equivalent global scope object. |
| 1.32.4 | AudioWorkletNode | `WAWorkletNode` | PARTIAL | `port` exists; full `options`/`parameters` parity is incomplete. |
| 1.32.4.x | AudioParamMap | - | MISSING | No `AudioWorkletNode.parameters` map interface exposed. |
| 1.32.5 | AudioWorkletProcessor | `WAWorkletProcessor` | PARTIAL | `process()` and `port` exist; full constructor/descriptor parity differs from spec. |

## 3) Immediate Gaps To Track First

- [ ] Implement `WAOfflineContext.startRendering()` backend path.
- [ ] Implement `WAParam.setValueCurveAtTime()` in JUCE + Web backends.
- [ ] Add missing node factories on `WAContext` for `ConstantSource`, `Convolver`, `IIRFilter`, `Panner`, media element/track sources.
- [ ] Add `AudioWorkletNode.parameters` parity (`AudioParamMap` equivalent).
- [ ] Add `AudioListener` and `PannerNode` 3D audio interfaces.
- [ ] Decide policy for deprecated interfaces (`ScriptProcessorNode`, `AudioProcessingEvent`): explicit non-goal vs compatibility shim.

## 4) Repro Commands

```bash
# Spec interface extraction (IDL index)
curl -sL https://www.w3.org/TR/webaudio-1.1/ -o /tmp/webaudio11.html
sed -n '14466,16080p' /tmp/webaudio11.html \
  | rg "<c- b>interface</c->" \
  | sed -E 's/.*<c- g>([A-Za-z0-9_]+)<\\/c->.*/\\1/' \
  | sort -u

# Local API scan
rg -n "^class\\s+WA|^abstract class\\s+WA" lib/src
rg -n "create[A-Za-z0-9_]+\\(" lib/src/context.dart lib/src/backend
rg -n "TODO|UnimplementedError" lib/src
```

