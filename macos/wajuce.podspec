#
# wajuce macOS podspec — JUCE-backed audio engine
#
# Compiles all JUCE modules + WajuceEngine in a single translation unit
# via the WajuceJUCE.mm unity build file.
#
Pod::Spec.new do |s|
  s.name             = 'wajuce'
  s.version          = '0.0.1'
  s.summary          = 'Web Audio API for Flutter, powered by JUCE.'
  s.description      = <<-DESC
Cross-platform audio engine using JUCE for native and Web Audio API for web.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'AcidApps' => 'dev@acidapps.io' }

  s.source           = { :path => '.' }
  s.source_files     = [
    'Classes/WajuceJUCE.mm',
    '../native/engine/Source/WajuceEngine.cpp',
    '../native/engine/vendor/JUCE/modules/juce_core/juce_core.mm',
    '../native/engine/vendor/JUCE/modules/juce_events/juce_events.mm',
    '../native/engine/vendor/JUCE/modules/juce_graphics/juce_graphics.mm',
    '../native/engine/vendor/JUCE/modules/juce_data_structures/juce_data_structures.mm',
    '../native/engine/vendor/JUCE/modules/juce_gui_basics/juce_gui_basics.mm',
    '../native/engine/vendor/JUCE/modules/juce_audio_basics/juce_audio_basics.mm',
    '../native/engine/vendor/JUCE/modules/juce_audio_devices/juce_audio_devices.mm',
    '../native/engine/vendor/JUCE/modules/juce_audio_formats/juce_audio_formats.mm',
    '../native/engine/vendor/JUCE/modules/juce_audio_processors/juce_audio_processors.mm',
    '../native/engine/vendor/JUCE/modules/juce_dsp/juce_dsp.mm',
  ]
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.13'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++20',
    'GCC_PREPROCESSOR_DEFINITIONS' => [
      'JUCE_MAC=1',
      'JUCE_GLOBAL_MODULE_SETTINGS_INCLUDED=1',
      'JUCE_DISPLAY_SPLASH_SCREEN=0',
      'JUCE_USE_DARK_SPLASH_SCREEN=0',
      'JUCE_STANDALONE_APPLICATION=0',
      'JUCE_MODULE_AVAILABLE_juce_audio_basics=1',
      'JUCE_MODULE_AVAILABLE_juce_audio_devices=1',
      'JUCE_MODULE_AVAILABLE_juce_audio_formats=1',
      'JUCE_MODULE_AVAILABLE_juce_audio_processors=1',
      'JUCE_MODULE_AVAILABLE_juce_core=1',
      'JUCE_MODULE_AVAILABLE_juce_data_structures=1',
      'JUCE_MODULE_AVAILABLE_juce_dsp=1',
      'JUCE_MODULE_AVAILABLE_juce_events=1',
      'JUCE_MODULE_AVAILABLE_juce_graphics=1',
      'JUCE_MODULE_AVAILABLE_juce_gui_basics=1',
    ].join(' '),
    'HEADER_SEARCH_PATHS' => [
      '"$(PODS_TARGET_SRCROOT)/../native/engine/vendor/JUCE/modules"',
      '"$(PODS_TARGET_SRCROOT)/../native/engine/Source"',
    ].join(' '),
    'OTHER_CPLUSPLUSFLAGS' => '-Wno-everything',
  }

  s.frameworks = 'AudioToolbox', 'CoreAudio', 'CoreMIDI', 'Accelerate',
                 'AudioUnit', 'Carbon', 'Cocoa', 'CoreFoundation',
                 'CoreServices', 'IOKit', 'Security', 'WebKit'
end
