---
name: juce_setup
description: Handles JUCE framework setup, dependency checks, and environment preparation for the wajuce project.
---

# JUCE Setup & Management Skill

This skill provides instructions for AI agents to set up and maintain the JUCE framework dependency required by the `wajuce` project.

## 1. Dependency Detection
Before any build or development task, verify if JUCE is correctly placed.

- **Required Path**: `native/engine/vendor/JUCE`
- **Check Command**: `ls -d native/engine/vendor/JUCE/modules`
- **Symptom 1 (Missing)**: Directory does not exist.
- **Symptom 2 (Broken Symlink)**: Directory exists but is a broken link (often pointing to a deleted `acidBros_flutter` path).

## 2. Setup Procedures

### Option A: Git Submodule (Recommended)
If the project is a Git repository, add JUCE as a submodule to ensure version consistency.

```zsh
# Clear existing broken links/dirs if any
rm -rf native/engine/vendor/JUCE

# Add submodule
git submodule add https://github.com/juce-framework/JUCE.git native/engine/vendor/JUCE

# Initialize
git submodule update --init --recursive
```

### Option B: Manual Download
If Git is not available or submodules are not preferred.

1. Download JUCE 8 from [juce.com](https://juce.com/download/).
2. Extract to `native/engine/vendor/JUCE`.
3. Verify that `native/engine/vendor/JUCE/CMakeLists.txt` exists.

## 3. Environment Verification
After setup, verify the environment can build the engine.

```zsh
cd native/engine
mkdir -p build
cmake -B build -S .
```

## 4. Handling Common Issues
- **CMake cannot find JUCE**: Ensure `native/engine/CMakeLists.txt` has the correct `add_subdirectory(vendor/JUCE ...)` path.
- **Compiler errors (C++17)**: Ensure the host compiler supports C++17 as required by JUCE 8 and `wajuce`.
- **Permission Denied**: If using a symlink, ensure the target has read permissions. (Avoid symlinks for portability; use Option A or B).

## 5. Integration Context
- JUCE is used by `native/engine/Source/WajuceEngine.cpp` via the `juce::AudioProcessorGraph`.
- The `wajuce` project acts as an FFI wrapper around this engine.
