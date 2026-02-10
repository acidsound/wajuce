# wajuce — Native library build
# Consumed by Flutter's plugin system for Android, Windows, Linux.
# macOS/iOS use CocoaPods which invokes this transitively.
#
# Build modes:
#   Default: links to JUCE C++ engine (Phase 2+)
#   WAJUCE_STUB_ONLY=ON: uses the C stub for analysis/testing without JUCE

cmake_minimum_required(VERSION 3.22)

project(wajuce_library VERSION 0.1.0 LANGUAGES C CXX)

option(WAJUCE_STUB_ONLY "Build with C stubs only (no JUCE dependency)" OFF)

if(WAJUCE_STUB_ONLY)
    # ---- Stub build (no JUCE required) ----
    add_library(wajuce SHARED
        "wajuce.c"
    )
    target_compile_definitions(wajuce PUBLIC DART_SHARED_LIB)
    set_target_properties(wajuce PROPERTIES
        PUBLIC_HEADER wajuce.h
        OUTPUT_NAME "wajuce"
    )
else()
    # ---- Full JUCE build ----
    add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../native/engine
                     ${CMAKE_CURRENT_BINARY_DIR}/engine)

    # The WajuceEngine target provides all extern "C" symbols via WajuceEngine.cpp
    # We create a shared library that re-exports those via linking.
    add_library(wajuce SHARED
        "wajuce.h"  # header-only source entry; symbols come from WajuceEngine
    )
    target_link_libraries(wajuce PRIVATE WajuceEngine)
    set_target_properties(wajuce PROPERTIES
        PUBLIC_HEADER wajuce.h
        OUTPUT_NAME "wajuce"
        CXX_STANDARD 17
        CXX_STANDARD_REQUIRED ON
        LINKER_LANGUAGE CXX
    )
    target_compile_definitions(wajuce PUBLIC DART_SHARED_LIB)
endif()
