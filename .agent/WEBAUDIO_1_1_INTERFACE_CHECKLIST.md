# Web Audio 1.1 Interface Coverage Checklist

- Updated: 2026-05-03
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
  - `lib/src/backend/backend_native.dart`
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
| 1.3 | OfflineAudioContext | `WAOfflineContext` | PARTIAL | Native `startRendering()` renders the graph into a `WABuffer`; web fallback still uses the browser realtime context path. |
| 1.3.5 | OfflineAudioCompletionEvent | - | MISSING | No equivalent interface/event. |
| 1.4 | AudioBuffer | `WABuffer` | IMPLEMENTED | Core attributes and `copyToChannel/copyFromChannel` exist. |
| 1.5 | AudioNode | `WANode` | PARTIAL | Node connect validates context/output/input bounds; `connectParam(WAParam)` and explicit output/node-input/param disconnect methods are native/web-backed. Dart names remain explicit because Dart has no JS-style overloads. |
| 1.6 | AudioParam | `WAParam` | IMPLEMENTED | Native/web `setValueCurveAtTime()` are wired; native `cancelAndHoldAtTime()` holds interpolated ramp values; native AudioParam input summing is covered by smoke tests. |
| 1.7 | AudioScheduledSourceNode | `WAScheduledSourceNode` | PARTIAL | Shared base type added; `onEnded` event dispatch is not yet backend-driven. |
| 1.8 | AnalyserNode | `WAAnalyserNode` | PARTIAL | `minDecibels/maxDecibels/smoothingTimeConstant` setters are wired; native analyser data path has smoke coverage. |
| 1.9 | AudioBufferSourceNode | `WABufferSourceNode` | PARTIAL | `start(when, offset, duration)`, `loopStart/loopEnd`, neutral default playback, and native scheduling tests are present. |
| 1.10 | AudioDestinationNode | `WADestinationNode` | PARTIAL | Destination exists with backend-provided `maxChannelCount`; full spec parity is still incomplete. |
| 1.11 | AudioListener | `WAAudioListener` | PARTIAL | Listener params feed native panner position calculations; full orientation model parity remains incomplete. |
| 1.12 | AudioProcessingEvent (deprecated) | `WAAudioProcessingEvent` | SHIM | Deprecated compatibility payload exposed as minimal shim only. |
| 1.13 | BiquadFilterNode | `WABiquadFilterNode` | PARTIAL | `getFrequencyResponse()` is native-backed and covered for baseline response; full spec edge cases remain open. |
| 1.14 | ChannelMergerNode | `WAChannelMergerNode` | IMPLEMENTED | Core constructor behavior present. |
| 1.15 | ChannelSplitterNode | `WAChannelSplitterNode` | IMPLEMENTED | Core constructor behavior present. |
| 1.16 | ConstantSourceNode | `WAConstantSourceNode` | IMPLEMENTED | Native node renders scheduled `offset`; start/stop smoke coverage is present. |
| 1.17 | ConvolverNode | `WAConvolverNode` | PARTIAL | Native FIR impulse-response processing is implemented; FFT partitioning/large IR performance parity remains open. |
| 1.18 | DelayNode | `WADelayNode` | IMPLEMENTED | `delayTime` exists; note extra non-spec `feedback` param is added. |
| 1.19 | DynamicsCompressorNode | `WADynamicsCompressorNode` | PARTIAL | `reduction` getter is native/web-backed; full compressor curve parity remains open. |
| 1.20 | GainNode | `WAGainNode` | IMPLEMENTED | Core interface is present. |
| 1.21 | IIRFilterNode | `WAIIRFilterNode` | IMPLEMENTED | Native direct-form processing and context-sample-rate frequency response are implemented. |
| 1.22 | MediaElementAudioSourceNode | `WAMediaElementSourceNode` | PARTIAL | API/factory added; web wired, WebAudio native falls back to stream source behavior. |
| 1.23 | MediaStreamAudioDestinationNode | `WAMediaStreamDestNode` | PARTIAL | `stream` property now exposed; available on web backend. |
| 1.24 | MediaStreamAudioSourceNode | `WAMediaStreamSourceNode` | PARTIAL | `mediaStream` property now exposed; available on web backend. |
| 1.25 | MediaStreamTrackAudioSourceNode | `WAMediaStreamTrackSourceNode` | PARTIAL | API/factory added; web wired, native media input is available through the realtime input path. |
| 1.26 | OscillatorNode | `WAOscillatorNode` | PARTIAL | Now aligned with `WAScheduledSourceNode`; full `onended` event parity is still incomplete. |
| 1.27 | PannerNode | `WAPannerNode` | PARTIAL | Native distance, cone, listener position, and equal-power pan behavior are implemented; HRTF parity remains open. |
| 1.28 | PeriodicWave | `WAPeriodicWave` | PARTIAL | `disableNormalization` now reaches native/web oscillator creation; constructor validation parity remains open. |
| 1.29 | ScriptProcessorNode (deprecated) | `WAScriptProcessorNode` | SHIM | Deprecated compatibility node exposed as minimal shim only. |
| 1.30 | StereoPannerNode | `WAStereoPannerNode` | IMPLEMENTED | Core `pan` param and node behavior present. |
| 1.31 | WaveShaperNode | `WAWaveShaperNode` | IMPLEMENTED | `curve` and `oversample` are exposed. |
| 1.32 | AudioWorklet | `WAWorklet` | PARTIAL | `addModule` + processor registration are present; full browser parity is not complete. |
| 1.32.3 | AudioWorkletGlobalScope | (emulated) | PARTIAL | Worklet execution environment exists via isolate/proxy model, not a spec-equivalent global scope object. |
| 1.32.4 | AudioWorkletNode | `WAWorkletNode` | PARTIAL | `port` plus `parameters` map exposed; Dart modules can register parameter descriptors and native/web Dart processors receive parameter blocks from current scalar param values. Full options parity remains incomplete. |
| 1.32.4.x | AudioParamMap | `WAAudioParamMap` | PARTIAL | Map wrapper is backed by registered parameter descriptors/defaults and scalar backend reads during worklet processing; full a-rate automation arrays remain open. |
| 1.32.5 | AudioWorkletProcessor | `WAWorkletProcessor` | PARTIAL | `process()` and `port` exist; full constructor/descriptor parity differs from spec. |

## 3) Immediate Gap Batch (1~6) Status

- [x] Implement `WAOfflineContext.startRendering()` native graph render path.
- [x] Implement `WAParam.setValueCurveAtTime()` in native + Web backends.
- [x] Add missing node factories on `WAContext` for `ConstantSource`, `Convolver`, `IIRFilter`, `Panner`, media element/track sources.
- [x] Add `AudioWorkletNode.parameters` parity (`AudioParamMap` equivalent, minimal map).
- [x] Add `AudioListener` and `PannerNode` 3D audio interfaces.
- [x] Deprecated policy applied as requested: minimal shim only for `ScriptProcessorNode` and `AudioProcessingEvent`.

## 4) Next Parity Gaps

- [ ] Native: full `AudioListener` / `PannerNode` HRTF/orientation model parity.
- [ ] Native: partitioned/FFT `ConvolverNode` processing for large impulse responses.
- [ ] Native/web: `onended` event dispatch driven by backend source completion.
- [ ] Native: compressed `decodeAudioData` parity on non-Apple platforms; Apple uses AudioToolbox fallback for system-supported compressed formats.
- [ ] `AudioWorkletNode.parameters` full a-rate automation arrays.
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
