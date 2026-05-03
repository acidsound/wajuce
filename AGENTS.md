# wajuce Agent Context (Updated 2026-05-03)

## Project Overview
`wajuce` is a Flutter package that exposes Web Audio API 1.1-style Dart APIs.
- Native (iOS/Android/macOS/Windows): iPlug2-backed C++ WebAudio runtime via FFI.
- Web: `dart:js_interop` wrapper over browser Web Audio API.
- Core goal: WebAudio 1.1-literate developers should port with minimal rewrite.

## Current Release Status
- Latest released version: `0.3.0`
- Main release theme: native runtime migration from JUCE to iPlug2.
- pub.dev publish for `0.3.0`: completed
- Publish quality checks at release time:
  - `dart analyze` passed
  - native CMake smoke test passed
  - `dart pub publish --dry-run`: `0 warnings`
  - `pana` score: `160/160`, dartdoc `0 warnings`

## Architecture Snapshot (Current)
- `WAContext` + node graph model is the core API surface.
- AudioWorklet flow is module-based:
  - Define in Dart with `WAWorkletModules.define(...)`
  - Load with `audioWorklet.addModule(...)`
  - Create with `createWorkletNode(processorName, ...)`
- Native cycle handling uses a spec-oriented one-block delayed feedback path.
- Web backend supports external worklet processors and port messaging.
- Conditional backends:
  - `dart.library.ffi` -> native FFI backend
  - `dart.library.js_interop` -> Web backend
  - stub fallback

## What Changed In 0.3.0 (Important)
- Native runtime migrated from JUCE to an iPlug2-backed WebAudio renderer.
- Old JUCE submodule and wrapper/native graph sources were removed.
- Native C ABI now resolves through `WAIPlugEngine`.
- iOS and macOS example builds were validated after the migration.
- Sequencer add-machine timing was stabilized with warm voice pooling,
  audio-time lookahead scheduling, inactive machine voices, and silent
  delay-branch skipping.

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
  - `lib/src/backend/backend_native.dart`
  - `lib/src/backend/backend_web.dart`
  - `lib/src/backend/backend_stub.dart`
- Native engine:
  - `native/engine/Source/WAIPlugEngine.cpp`
  - `native/engine/Source/WAIPlugEngine.h`
  - `native/engine/Source/ParamAutomation.h`
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
