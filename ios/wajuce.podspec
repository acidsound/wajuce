#
# wajuce iOS podspec — JUCE-backed audio engine
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
  s.source_files     = 'Classes/**/*.{h,m,mm,c,cpp}'
  s.dependency 'Flutter'

  s.platform = :ios, '12.0'
  s.requires_arc = false
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++20',
    'GCC_PREPROCESSOR_DEFINITIONS' => [
      'JUCE_DISPLAY_SPLASH_SCREEN=0',
      'JUCE_USE_DARK_SPLASH_SCREEN=0',
      'JUCE_STANDALONE_APPLICATION=0',
      'JUCE_IOS=1',
      'JUCE_GLOBAL_MODULE_SETTINGS_INCLUDED=1',
      'JUCE_MODULE_AVAILABLE_juce_audio_basics=1',
      'JUCE_MODULE_AVAILABLE_juce_audio_devices=1',
      'JUCE_MODULE_AVAILABLE_juce_audio_formats=1',
      'JUCE_MODULE_AVAILABLE_juce_audio_processors=1',
      'JUCE_MODULE_AVAILABLE_juce_audio_processors_headless=1',
      'JUCE_MODULE_AVAILABLE_juce_core=1',
      'JUCE_MODULE_AVAILABLE_juce_data_structures=1',
      'JUCE_MODULE_AVAILABLE_juce_dsp=1',
      'JUCE_MODULE_AVAILABLE_juce_events=1',
      'JUCE_MODULE_AVAILABLE_juce_graphics=1',
      'JUCE_MODULE_AVAILABLE_juce_gui_basics=1',
      'JUCE_MODULE_AVAILABLE_juce_gui_extra=1',
      'JUCE_WEB_BROWSER=0',
      'JUCE_USE_CURL=0',
    ].join(' '),
    'HEADER_SEARCH_PATHS' => [
       '"$(PODS_TARGET_SRCROOT)/../native/engine/vendor/JUCE/modules"',
       '"$(PODS_TARGET_SRCROOT)/../native/engine/Source"',
    ].join(' '),
    'OTHER_CFLAGS' => '-fno-objc-arc -Wno-everything',
    'OTHER_CPLUSPLUSFLAGS' => '-fno-objc-arc -Wno-everything',
  }

  s.frameworks = 'AVFoundation', 'AudioToolbox', 'CoreAudio', 'CoreAudioKit',
                 'CoreMIDI', 'Accelerate', 'QuartzCore', 'CoreGraphics',
                 'UIKit', 'Foundation', 'MobileCoreServices', 'UniformTypeIdentifiers'
end
