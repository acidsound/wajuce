# iOS Simulator Tutorial Capture Pipeline

## Goal
Build a repeatable pipeline that captures:
- iOS Simulator screen video
- app audio via BlackHole
- timeline text track (LRC) for tutorial overlays or captions

This is designed for running `example/lib/main.dart` and turning the run into a reusable tutorial asset.

## Core Idea
Do not rely on "start both recorders at the same millisecond".
Use a sync marker event and align tracks in post:
1. Record screen with `xcrun simctl io ... recordVideo`.
2. Record audio with `ffmpeg` from BlackHole.
3. Trigger a clear marker in app (flash + click/beep).
4. Trim/align by marker times and mux into final MP4.
5. Generate an LRC timeline from step definitions.

This works well for automation and is robust against process startup jitter.

## Prerequisites
- macOS with Xcode command line tools (`xcrun`, `simctl`)
- Flutter SDK
- `ffmpeg`
- BlackHole installed (already present in this environment)
- iOS Simulator booted

Audio routing note:
- Ensure app output reaches the BlackHole input you capture.
- Typical setup: Multi-Output Device (Speakers + BlackHole) as system output.

## Added Scripts
- `tool/tutorial_capture/capture_ios_demo.sh`
- `tool/tutorial_capture/sync_and_mux.sh`
- `tool/tutorial_capture/generate_lrc.sh`
- `tool/tutorial_capture/steps.example.tsv`

## Quick Start
All commands below assume the current working directory is the repository root.

### 1) Capture raw tracks
```bash
tool/tutorial_capture/capture_ios_demo.sh \
  --audio-device-name "BlackHole 2ch" \
  --pre-video-beep \
  --flutter-extra-args '--dart-define=WAJUCE_AUTODEMO=true --dart-define=WAJUCE_AUTODEMO_DISABLE_SYNC_BEEP=true --dart-define=WAJUCE_AUTODEMO_START_DELAY_MS=2500' \
  --duration-sec 20
```

This creates:
- `screen_raw.mp4`
- `audio_raw.wav`
- logs and a summary file

By default output goes to:
- `example/captures/<timestamp>/`

### 2) Align and mux
Find marker times (manual inspection), then:
```bash
tool/tutorial_capture/sync_and_mux.sh \
  --video example/captures/<timestamp>/screen_raw.mp4 \
  --audio example/captures/<timestamp>/audio_raw.wav \
  --video-marker-sec 1.22 \
  --audio-marker-sec 0.87 \
  --output example/captures/<timestamp>/final_synced.mp4
```

### 3) Generate LRC timeline
Prepare step file (`relative_sec<TAB>text`) and run:
```bash
tool/tutorial_capture/generate_lrc.sh \
  --steps tool/tutorial_capture/steps.example.tsv \
  --sync-sec 0.00 \
  --title "wajuce tutorial" \
  --output example/captures/<timestamp>/tutorial.lrc
```

## Example LRC Use Cases
- Subtitle source for tutorial rendering
- Guidance timeline for QA replay
- Input to post-processing tools that place captions or chapter markers

## Generalization Potential
This pipeline can evolve into a reusable "demo build bot":
- fixed capture profile per app/simulator
- deterministic scripted interactions (`integration_test`)
- standardized output bundle: MP4 + LRC + artifact manifest
- optional auto-publish into release notes or docs

## Recommended Next Step
Add one dedicated in-app sync action in the example app:
- visual flash for video marker
- short click/beep for audio marker

That single feature makes synchronization deterministic for every run.
