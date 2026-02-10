/**
 * WajuceJUCE.mm — macOS/iOS unity-build file for the JUCE-backed wajuce engine.
 *
 * This single Objective-C++ file includes all required JUCE modules plus
 * the wajuce engine source files.  CocoaPods compiles this in one
 * translation unit, avoiding the need for CMake on Apple platforms.
 *
 * Header search paths in the podspec point to:
 *   - native/engine/vendor/JUCE/modules (for JUCE module headers)
 *   - native/engine/Source (for WajuceEngine.h etc.)
 *
 * The JUCE .mm unity files are included via their relative path from
 * the JUCE/modules root (which is on the header search path).
 */

// ---- JUCE module unity includes (Objective-C++ versions for Apple) ----
// The podspec sets -Wno-everything to suppress warnings inside JUCE code.

#include "juce_audio_basics/juce_audio_basics.mm"
#include "juce_audio_devices/juce_audio_devices.mm"
#include "juce_audio_formats/juce_audio_formats.mm"
#include "juce_audio_processors/juce_audio_processors.mm"
#include "juce_core/juce_core.mm"
#include "juce_data_structures/juce_data_structures.mm"
#include "juce_dsp/juce_dsp.mm"
#include "juce_events/juce_events.mm"

// ---- Wajuce engine (C++ source included as part of this TU) ----
#include "WajuceEngine.cpp"
