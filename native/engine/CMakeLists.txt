cmake_minimum_required(VERSION 3.22)

project(WajuceEngine VERSION 0.1.0 LANGUAGES C CXX)

# JUCE — use vendor copy (shared with acidBros_flutter)
add_subdirectory(vendor/JUCE ${CMAKE_CURRENT_BINARY_DIR}/JUCE EXCLUDE_FROM_ALL)

# Engine static library
add_library(WajuceEngine STATIC
    Source/WajuceEngine.cpp
    Source/WajuceEngine.h
    Source/NodeRegistry.h
    Source/Processors.h
    Source/ParamAutomation.h
)

# JUCE modules
target_link_libraries(WajuceEngine
    PRIVATE
        juce::juce_audio_basics
        juce::juce_audio_devices
        juce::juce_audio_formats
        juce::juce_audio_processors
        juce::juce_core
        juce::juce_dsp
        juce::juce_events
)

set_target_properties(WajuceEngine PROPERTIES
    POSITION_INDEPENDENT_CODE ON
    C_VISIBILITY_PRESET default
    CXX_VISIBILITY_PRESET default
    VISIBILITY_INLINES_HIDDEN OFF
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
    CXX_EXTENSIONS OFF
)

target_include_directories(WajuceEngine PUBLIC Source)
