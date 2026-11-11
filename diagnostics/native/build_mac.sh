#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun --sdk iphoneos clang -target arm64-apple-ios15.0 -isysroot "$SDK" -fobjc-arc -O2 \
  -fvisibility=hidden -dynamiclib -Wl,-install_name,@rpath/DeltaFrameTrace.dylib \
  -framework Foundation -framework UIKit -framework QuartzCore -framework Metal \
  -o "$ROOT/DeltaFrameTrace.dylib" "$ROOT/DeltaFrameTrace.m"
file "$ROOT/DeltaFrameTrace.dylib"
xcrun vtool -show-build "$ROOT/DeltaFrameTrace.dylib"
shasum -a 256 "$ROOT/DeltaFrameTrace.dylib"

