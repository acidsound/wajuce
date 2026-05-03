# wajuce — Native library build
# Consumed by Flutter's plugin system for Android, Windows, Linux.
# macOS/iOS use CocoaPods which invokes this transitively.
#
# Build modes:
#   Default: links to the iPlug2-backed native WebAudio engine
#   WAJUCE_STUB_ONLY=ON: uses the C stub for analysis/testing

cmake_minimum_required(VERSION 3.22)

project(wajuce_library VERSION 0.1.0 LANGUAGES C CXX)

option(WAJUCE_STUB_ONLY "Build with C stubs only (no native audio runtime)" OFF)

if(WAJUCE_STUB_ONLY)
    # ---- Stub build ----
    add_library(wajuce SHARED
        "wajuce.c"
    )
    target_compile_definitions(wajuce PUBLIC DART_SHARED_LIB)
    set_target_properties(wajuce PROPERTIES
        PUBLIC_HEADER wajuce.h
        OUTPUT_NAME "wajuce"
    )
else()
    # ---- Full native build ----
    add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../native/engine
                     ${CMAKE_CURRENT_BINARY_DIR}/engine)

    # WAIPlugEngine provides all extern "C" symbols.
    # We create a shared library that re-exports those via linking.
    add_library(wajuce SHARED
        "wajuce.h"  # header-only source entry; symbols come from WAIPlugEngine
    )
    if(APPLE)
        target_link_libraries(wajuce PRIVATE WAIPlugEngine)
        target_link_options(wajuce PRIVATE
            "LINKER:-force_load,$<TARGET_FILE:WAIPlugEngine>")
    elseif(MSVC)
        target_link_libraries(wajuce PRIVATE WAIPlugEngine)
        target_link_options(wajuce PRIVATE
            "/WHOLEARCHIVE:$<TARGET_FILE:WAIPlugEngine>")
    else()
        target_link_libraries(wajuce PRIVATE
            "-Wl,--whole-archive" WAIPlugEngine "-Wl,--no-whole-archive")
    endif()
    set_target_properties(wajuce PROPERTIES
        PUBLIC_HEADER wajuce.h
        OUTPUT_NAME "wajuce"
        CXX_STANDARD 17
        CXX_STANDARD_REQUIRED ON
        LINKER_LANGUAGE CXX
    )
    target_compile_definitions(wajuce PUBLIC DART_SHARED_LIB)
endif()
