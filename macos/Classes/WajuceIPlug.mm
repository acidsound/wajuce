#import <Foundation/Foundation.h>

// CocoaPods may ignore source files outside the macOS pod root when this plugin
// is consumed by Flutter. Include the native runtime here so the macOS
// framework exports the Dart FFI C ABI symbols consistently with iOS.
#include "../../native/engine/Source/WAIPlugEngine.cpp"
