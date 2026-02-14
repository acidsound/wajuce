# Web Audio 1.1 Interface Coverage Checklist

- Updated: 2026-02-14
- Spec source: https://www.w3.org/TR/webaudio-1.1/
- Scope: interface-level parity check for `wajuce` public Dart API and backend wiring.

## Legend

- `IMPLEMENTED`: Interface exists and core API surface is present.
- `PARTIAL`: Interface exists but important members/behavior are missing.
- `MISSING`: No corresponding public API in `wajuce`.
- `SHIM`: Deprecated interface exposed only as minimal compatibility wrapper.

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
| 1.1 | BaseAudioContext | `WAContext` | PARTIAL | Core attrs/factories expanded (`listener`, panner/convolver/iir/constant/media sources), but full overload parity is still incomplete. |
| 1.2 | AudioContext | `WAContext` | PARTIAL | `baseLatency/outputLatency/sinkId/getOutputTimestamp/renderCapacity` added; full sink management/event parity remains incomplete. |
| 1.2.7 | AudioSinkInfo | `WAAudioSinkInfo` | PARTIAL | Minimal wrapper exposed; full spec shape is not complete. |
| 1.2.9 | AudioRenderCapacity | `WAAudioRenderCapacity` | PARTIAL | Minimal polling/onUpdate wrapper; not full browser API parity. |
| 1.2.11 | AudioRenderCapacityEvent | `WAAudioRenderCapacityEvent` | PARTIAL | Minimal event payload shape exposed. |
| 1.3 | OfflineAudioContext | `WAOfflineContext` | PARTIAL | `startRendering()` now returns an allocated output buffer; full graph render path is pending. |
| 1.3.5 | OfflineAudioCompletionEvent | - | MISSING | No equivalent interface/event. |
| 1.4 | AudioBuffer | `WABuffer` | IMPLEMENTED | Core attributes and `copyToChannel/copyFromChannel` exist. |
| 1.5 | AudioNode | `WANode` | PARTIAL | Basic connect/disconnect exists, but full overload set and AudioParam destination connect are missing. |
| 1.6 | AudioParam | `WAParam` | IMPLEMENTED | `setValueCurveAtTime()` backend path added (web native API, JUCE fallback via scheduled points). |
| 1.7 | AudioScheduledSourceNode | `WAScheduledSourceNode` | PARTIAL | Shared base type added; `onEnded` event dispatch is not yet backend-driven. |
| 1.8 | AnalyserNode | `WAAnalyserNode` | PARTIAL | `minDecibels/maxDecibels/smoothingTimeConstant` setters are wired; native behavior remains backend-dependent. |
| 1.9 | AudioBufferSourceNode | `WABufferSourceNode` | PARTIAL | Added `start(when, offset, duration)` and `loopStart/loopEnd`; native backend still has partial scheduling support. |
| 1.10 | AudioDestinationNode | `WADestinationNode` | PARTIAL | Destination exists with backend-provided `maxChannelCount`; full spec parity is still incomplete. |
| 1.11 | AudioListener | `WAAudioListener` | PARTIAL | Listener params and legacy methods added; native backend currently no-ops listener control. |
| 1.12 | AudioProcessingEvent (deprecated) | `WAAudioProcessingEvent` | SHIM | Deprecated compatibility payload exposed as minimal shim only. |
| 1.13 | BiquadFilterNode | `WABiquadFilterNode` | PARTIAL | `getFrequencyResponse()` wired; native backend currently returns fallback response values. |
| 1.14 | ChannelMergerNode | `WAChannelMergerNode` | IMPLEMENTED | Core constructor behavior present. |
| 1.15 | ChannelSplitterNode | `WAChannelSplitterNode` | IMPLEMENTED | Core constructor behavior present. |
| 1.16 | ConstantSourceNode | `WAConstantSourceNode` | PARTIAL | API and factory added; JUCE currently uses an emulated fallback node. |
| 1.17 | ConvolverNode | `WAConvolverNode` | PARTIAL | API and web backend wiring added; JUCE currently fallback/pass-through. |
| 1.18 | DelayNode | `WADelayNode` | IMPLEMENTED | `delayTime` exists; note extra non-spec `feedback` param is added. |
| 1.19 | DynamicsCompressorNode | `WADynamicsCompressorNode` | PARTIAL | `reduction` getter is backend-wired (web); JUCE currently returns fallback `0.0`. |
| 1.20 | GainNode | `WAGainNode` | IMPLEMENTED | Core interface is present. |
| 1.21 | IIRFilterNode | `WAIIRFilterNode` | PARTIAL | API/factory added with response query; JUCE processing path is currently emulated via biquad fallback. |
| 1.22 | MediaElementAudioSourceNode | `WAMediaElementSourceNode` | PARTIAL | API/factory added; web wired, JUCE falls back to stream source behavior. |
| 1.23 | MediaStreamAudioDestinationNode | `WAMediaStreamDestNode` | PARTIAL | `stream` property now exposed; available on web backend. |
| 1.24 | MediaStreamAudioSourceNode | `WAMediaStreamSourceNode` | PARTIAL | `mediaStream` property now exposed; available on web backend. |
| 1.25 | MediaStreamTrackAudioSourceNode | `WAMediaStreamTrackSourceNode` | PARTIAL | API/factory added; web wired, JUCE uses fallback source behavior. |
| 1.26 | OscillatorNode | `WAOscillatorNode` | PARTIAL | Now aligned with `WAScheduledSourceNode`; full `onended` event parity is still incomplete. |
| 1.27 | PannerNode | `WAPannerNode` | PARTIAL | 3D panner API/factory added; JUCE currently maps to stereo/fallback behavior. |
| 1.28 | PeriodicWave | `WAPeriodicWave` | PARTIAL | Type exists and is usable via oscillator; full option/constraint parity is incomplete. |
| 1.29 | ScriptProcessorNode (deprecated) | `WAScriptProcessorNode` | SHIM | Deprecated compatibility node exposed as minimal shim only. |
| 1.30 | StereoPannerNode | `WAStereoPannerNode` | IMPLEMENTED | Core `pan` param and node behavior present. |
| 1.31 | WaveShaperNode | `WAWaveShaperNode` | IMPLEMENTED | `curve` and `oversample` are exposed. |
| 1.32 | AudioWorklet | `WAWorklet` | PARTIAL | `addModule` + processor registration are present; full browser parity is not complete. |
| 1.32.3 | AudioWorkletGlobalScope | (emulated) | PARTIAL | Worklet execution environment exists via isolate/proxy model, not a spec-equivalent global scope object. |
| 1.32.4 | AudioWorkletNode | `WAWorkletNode` | PARTIAL | `port` plus minimal `parameters` map exposed; full options/descriptor parity remains incomplete. |
| 1.32.4.x | AudioParamMap | `WAAudioParamMap` | PARTIAL | Minimal map wrapper added from parameter defaults; not yet backed by full runtime param introspection. |
| 1.32.5 | AudioWorkletProcessor | `WAWorkletProcessor` | PARTIAL | `process()` and `port` exist; full constructor/descriptor parity differs from spec. |

## 3) Immediate Gap Batch (1~6) Status

- [x] Implement `WAOfflineContext.startRendering()` backend path (minimal allocated output buffer path).
- [x] Implement `WAParam.setValueCurveAtTime()` in JUCE + Web backends.
- [x] Add missing node factories on `WAContext` for `ConstantSource`, `Convolver`, `IIRFilter`, `Panner`, media element/track sources.
- [x] Add `AudioWorkletNode.parameters` parity (`AudioParamMap` equivalent, minimal map).
- [x] Add `AudioListener` and `PannerNode` 3D audio interfaces.
- [x] Deprecated policy applied as requested: minimal shim only for `ScriptProcessorNode` and `AudioProcessingEvent`.

## 4) Next Parity Gaps

- [ ] Native JUCE: full `AudioListener` / `PannerNode` 3D spatial model parity.
- [ ] Native JUCE: full `ConvolverNode` impulse-response processing.
- [ ] Native JUCE: true `ConstantSourceNode.offset` behavior parity.
- [ ] `OfflineAudioContext.startRendering()` real graph render path (current path is minimal allocation).
- [ ] `AudioWorkletNode.parameters` backend-driven introspection beyond defaults.
## 5) Repro Commands

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
