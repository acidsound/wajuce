---
name: iplug2_runtime_setup
description: Handles iPlug2 runtime setup, dependency checks, and environment preparation for the wajuce project.
---

# iPlug2 Runtime Setup

This skill provides instructions for maintaining the native iPlug2-backed
runtime dependency required by the `wajuce` project.

## 1. Dependency Detection

- **Required Path**: `native/engine/vendor/iPlug2`
- **Check Command**: `test -f native/engine/vendor/iPlug2/iPlug2.cmake`
- **Symptom (Missing)**: the CMake file does not exist.

## 2. Setup Procedure

Use the repository submodule:

```zsh
git submodule update --init --recursive native/engine/vendor/iPlug2
```

## 3. Environment Verification

```zsh
cmake -S src -B build/native
cmake --build build/native
```

## 4. Integration Context

- Native symbols are implemented by `native/engine/Source/WAIPlugEngine.cpp`.
- Desktop real-time I/O uses RtAudio/RTMidi from the iPlug2 dependency tree.
- Dart talks to the native runtime through the stable C ABI in `src/wajuce.h`.
