#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
MODE=${1:-device}
if [[ $(uname -s) != Darwin ]]; then echo 'La compilación requiere macOS/Xcode. Usá el workflow Build iOS.' >&2; exit 1; fi
if [[ $MODE == device ]]; then
  SDK=iphoneos; TARGET=aarch64-apple-ios; CLANG_TARGET=arm64-apple-ios18.0
elif [[ $MODE == simulator ]]; then
  SDK=iphonesimulator
  if [[ $(uname -m) == arm64 ]]; then TARGET=aarch64-apple-ios-sim; CLANG_TARGET=arm64-apple-ios18.0-simulator
  else TARGET=x86_64-apple-ios; CLANG_TARGET=x86_64-apple-ios18.0-simulator; fi
else echo 'Usage: build.sh device|simulator' >&2; exit 2; fi
export IPHONEOS_DEPLOYMENT_TARGET=18.0
export SDKROOT=$(xcrun --sdk "$SDK" --show-sdk-path)
rustup target add "$TARGET"
(cd "$ROOT/src/OpenGMK" && cargo rustc --locked --release --lib -p gm8emulator --target "$TARGET" --crate-type staticlib)
OUT="$ROOT/ios/out/$MODE"
APP="$OUT/Payload/Reloaded.app"
mkdir -p "$APP"
xcrun --sdk "$SDK" clang -target "$CLANG_TARGET" -isysroot "$SDKROOT" -fobjc-arc -fblocks -O2 -Wno-deprecated-declarations \
  "$ROOT/ios/App.m" "$ROOT/src/OpenGMK/target/$TARGET/release/libgm8emulator.a" \
  -framework UIKit -framework CoreGraphics -framework QuartzCore -framework OpenGLES -framework AVFoundation \
  -framework AudioToolbox -framework UniformTypeIdentifiers -framework Foundation \
  -framework CoreFoundation -framework Security -framework SystemConfiguration \
  -lc++ -liconv -lz -lresolv -o "$APP/Reloaded"
cp "$ROOT/ios/Info.plist" "$APP/Info.plist"
cp "$ROOT/android/app/src/main/assets/soundfont.sf2" "$APP/soundfont.sf2"
mkdir -p "$APP/Controls"
cp "$ROOT/android/app/src/main/assets/"*.png "$APP/Controls/"
cp "$ROOT/android/app/src/main/assets/"*_catalog.csv "$APP/Controls/"
cp "$ROOT/LICENSE" "$APP/LICENSE.txt"
/usr/libexec/PlistBuddy -c "Add :CFBundleSupportedPlatforms array" "$APP/Info.plist"
if [[ $MODE == device ]]; then
 /usr/libexec/PlistBuddy -c "Add :CFBundleSupportedPlatforms:0 string iPhoneOS" "$APP/Info.plist"
 (cd "$OUT" && ditto -c -k --keepParent Payload Reloaded-iOS-0.2.0-unsigned.ipa)
 shasum -a 256 "$OUT/Reloaded-iOS-0.2.0-unsigned.ipa" > "$OUT/SHA256.txt"
else
 /usr/libexec/PlistBuddy -c "Add :CFBundleSupportedPlatforms:0 string iPhoneSimulator" "$APP/Info.plist"
 codesign --force --sign - "$APP"
fi
printf 'Built: %s\n' "$APP"
