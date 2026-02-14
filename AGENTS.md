# wajuce Agent Context (Updated 2026-02-14)

## Project Overview
`wajuce` is a Flutter package that exposes Web Audio API 1.1-style Dart APIs.
- Native (iOS/Android/macOS/Windows): JUCE C++ engine via FFI.
- Web: `dart:js_interop` wrapper over browser Web Audio API.
- Core goal: WebAudio 1.1-literate developers should port with minimal rewrite.

## Current Release Status
- Latest released version: `0.1.4`
- Git release commit: `6a63e60` (`tag: v0.1.4`)
- pub.dev publish for `0.1.4`: completed
- Publish quality checks at release time:
  - `dart analyze` passed
  - `pana` score: `160/160`
  - `dart pub publish --dry-run`: `0 warnings`

## Architecture Snapshot (Current)
- `WAContext` + node graph model is the core API surface.
- AudioWorklet flow is module-based:
  - Define in Dart with `WAWorkletModules.define(...)`
  - Load with `audioWorklet.addModule(...)`
  - Create with `createWorkletNode(processorName, ...)`
- Native cycle handling uses `FeedbackSender/FeedbackReceiver` bridge (1-block delay).
- Web backend supports external worklet processors and port messaging.
- Conditional backends:
  - `dart.library.ffi` -> JUCE backend
  - `dart.library.js_interop` -> Web backend
  - stub fallback

## What Changed In 0.1.4 (Important)
- Worklet module ergonomics and addModule flow were refactored.
- `createMachineVoiceAsync()` is deprecated in favor of synchronous batch creation.
- Sequencer/clock example moved to helper-driven worklet usage.
- Native machine voice routing fixed to true stereo (not left-only effective routing).
- Native machine voice feedback path restored with managed bridge:
  - `Delay -> Gain -> (bridge) -> Delay` loop works continuously.
- Delay behavior aligned with WebAudio usage pattern in example:
  - `delayTime` stays synchronized independently of wet bypass.
- Mic monitor behavior improved for mono-input environments (iOS upmix behavior).
- Package docs/license/changelog/pub ignore rules updated for pub.dev quality.

## Deep-Dive Handoff
Read this first for recent debugging context and implementation rationale:
- `.agent/HANDOFF_2026-02-14.md`

Then read baseline architecture/plans:
1. `.agent/wajuce_architect.md`
2. `.agent/implementation_plan.md`
3. `.agent/PROJECT_CONTEXT.md`

## Key Files To Inspect First
- Dart API/core:
  - `lib/src/context.dart`
  - `lib/src/audio_param.dart`
  - `lib/src/worklet/wa_worklet.dart`
  - `lib/src/worklet/wa_worklet_module.dart`
  - `lib/src/worklet/wa_worklet_node.dart`
- Backends:
  - `lib/src/backend/backend_juce.dart`
  - `lib/src/backend/backend_web.dart`
  - `lib/src/backend/backend_stub.dart`
- Native engine:
  - `native/engine/Source/WajuceEngine.mm`
  - `native/engine/Source/Processors.h`
  - `native/engine/Source/ParamAutomation.h`
  - `native/engine/Source/NodeRegistry.h`
- Example under active validation:
  - `example/lib/main.dart`
  - `example/lib/clock_processor.dart`

## Operational Notes For Next Agent
- Keep behavior spec-driven, not heuristic-driven, for WebAudio parity.
- Do not couple `DelayNode.delayTime` updates to effect bypass state.
- For feedback loops on native graph, use bridge nodes instead of direct cycles.
- If touching publish metadata, re-run:
  - `dart analyze`
  - `~/.pub-cache/bin/pana --no-warning --source path .`
  - `dart pub publish --dry-run`

## Current Workspace State
- Expected untracked local file:
  - `AGENTS.md` (this file, may be intentionally untracked in some local flows)
