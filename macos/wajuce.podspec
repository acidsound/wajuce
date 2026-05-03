#
# wajuce macOS podspec
#
Pod::Spec.new do |s|
  s.name             = 'wajuce'
  s.version          = '0.0.1'
  s.summary          = 'Web Audio API for Flutter, powered by an iPlug2-backed native engine.'
  s.description      = <<-DESC
Cross-platform Web Audio API implementation for Flutter.
                       DESC
  s.homepage         = 'https://github.com/acidsound/wajuce'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'AcidApps' => 'dev@acidapps.io' }

  s.source           = { :path => '.' }
  s.source_files     = [
    'Classes/WajuceIPlug.mm',
    'Classes/WajuceRtAudio.cpp',
    'Classes/WajuceRtMidi.cpp',
  ]
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.13'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'GCC_PREPROCESSOR_DEFINITIONS' => [
      'WAJUCE_USE_RTAUDIO=1',
      'WAJUCE_USE_RTMIDI=1',
      '__MACOSX_CORE__',
    ].join(' '),
    'HEADER_SEARCH_PATHS' => [
      '"$(PODS_TARGET_SRCROOT)/../native/engine/Source"',
      '"$(PODS_TARGET_SRCROOT)/../native/engine/vendor/iPlug2/IPlug"',
      '"$(PODS_TARGET_SRCROOT)/../native/engine/vendor/iPlug2/WDL"',
      '"$(PODS_TARGET_SRCROOT)/../native/engine/vendor/iPlug2/Dependencies/IPlug/RTAudio"',
      '"$(PODS_TARGET_SRCROOT)/../native/engine/vendor/iPlug2/Dependencies/IPlug/RTAudio/include"',
      '"$(PODS_TARGET_SRCROOT)/../native/engine/vendor/iPlug2/Dependencies/IPlug/RTMidi"',
    ].join(' '),
    'OTHER_CPLUSPLUSFLAGS' => '-Wno-everything',
  }

  s.frameworks = 'AudioToolbox', 'CoreAudio', 'CoreMIDI', 'CoreFoundation',
                 'Foundation'
end
