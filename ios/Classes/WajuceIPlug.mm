#import <Foundation/Foundation.h>

// CocoaPods does not add source files outside the iOS pod root to this target
// reliably. Include the native runtime here so the iOS framework exports the
// Dart FFI C ABI symbols.
#include "../../native/engine/Source/WAIPlugEngine.cpp"
