cmake_minimum_required(VERSION 3.22)

project(WAIPlugEngine VERSION 0.1.0 LANGUAGES C CXX)
option(WAJUCE_BUILD_NATIVE_TESTS "Build native WebAudio render tests" OFF)

set(IPLUG2_DIR "${CMAKE_CURRENT_SOURCE_DIR}/vendor/iPlug2" CACHE PATH
    "iPlug2 root directory")
if(NOT EXISTS "${IPLUG2_DIR}/iPlug2.cmake")
    message(FATAL_ERROR "iPlug2 runtime not found. Run: git submodule update --init --recursive native/engine/vendor/iPlug2")
endif()

# Engine static library
add_library(WAIPlugEngine STATIC
    Source/WAIPlugEngine.cpp
    Source/WAIPlugEngine.h
    Source/ParamAutomation.h
    Source/RingBuffer.h
)

set(IPLUG2_RTAUDIO_DIR
    "${IPLUG2_DIR}/Dependencies/IPlug/RTAudio")
set(IPLUG2_RTMIDI_DIR
    "${IPLUG2_DIR}/Dependencies/IPlug/RTMidi")

target_include_directories(WAIPlugEngine
    PUBLIC
        Source
    PRIVATE
        "${IPLUG2_DIR}/IPlug"
        "${IPLUG2_RTAUDIO_DIR}"
        "${IPLUG2_RTAUDIO_DIR}/include"
        "${IPLUG2_RTMIDI_DIR}"
)

if(APPLE AND NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
    target_sources(WAIPlugEngine PRIVATE
        "${IPLUG2_RTAUDIO_DIR}/RtAudio.cpp"
        "${IPLUG2_RTMIDI_DIR}/RtMidi.cpp"
    )
    target_compile_definitions(WAIPlugEngine PRIVATE
        WAJUCE_USE_RTAUDIO=1
        WAJUCE_USE_RTMIDI=1
        __MACOSX_CORE__
    )
    target_link_libraries(WAIPlugEngine PRIVATE
        "-framework CoreAudio"
        "-framework CoreFoundation"
        "-framework CoreMIDI"
        "-framework AudioToolbox"
    )
elseif(WIN32)
    target_sources(WAIPlugEngine PRIVATE
        "${IPLUG2_RTAUDIO_DIR}/RtAudio.cpp"
        "${IPLUG2_RTMIDI_DIR}/RtMidi.cpp"
    )
    target_compile_definitions(WAIPlugEngine PRIVATE
        WAJUCE_USE_RTAUDIO=1
        WAJUCE_USE_RTMIDI=1
        __WINDOWS_WASAPI__
        __WINDOWS_MM__
        NOMINMAX
    )
    target_link_libraries(WAIPlugEngine PRIVATE
        winmm
        ole32
        avrt
        ksuser
        mfplat
        mfuuid
        wmcodecdspuuid
    )
else()
    target_compile_definitions(WAIPlugEngine PRIVATE
        WAJUCE_USE_RTAUDIO=0
        WAJUCE_USE_RTMIDI=0
    )
endif()

set_target_properties(WAIPlugEngine PROPERTIES
    POSITION_INDEPENDENT_CODE ON
    C_VISIBILITY_PRESET default
    CXX_VISIBILITY_PRESET default
    VISIBILITY_INLINES_HIDDEN OFF
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
    CXX_EXTENSIONS OFF
)

if(WAJUCE_BUILD_NATIVE_TESTS)
    enable_testing()
    add_executable(wajuce_webaudio_render_smoke
        tests/webaudio_render_smoke.cpp
    )
    target_link_libraries(wajuce_webaudio_render_smoke PRIVATE WAIPlugEngine)
    target_include_directories(wajuce_webaudio_render_smoke PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/Source"
        "${CMAKE_CURRENT_SOURCE_DIR}/../../src"
    )
    add_test(NAME wajuce_webaudio_render_smoke
             COMMAND wajuce_webaudio_render_smoke)
endif()
