#!/bin/sh
# Xcode pre-build: the client as a static library for the SDK being built.
set -e
export PATH="$HOME/.cargo/bin:$PATH"
case "$PLATFORM_NAME" in
  iphonesimulator) TARGET=aarch64-apple-ios-sim ;;
  *) TARGET=aarch64-apple-ios ;;
esac
cd "$SRCROOT/.."
# Xcode's environment points cc at the iOS SDK for the wrong arch/target; let cargo/cc pick their own
IPHONEOS_DEPLOYMENT_TARGET=17.0 env -u SDKROOT -u LIBRARY_PATH -u CC -u CXX -u LD \
  cargo rustc --release --target "$TARGET" -p nostalre-client --lib --crate-type staticlib
# mlua-sys links Lua as its own native library (-llua5.1), not bundled into the staticlib: keep a copy
# at a fixed path beside it for the link
LUA=$(ls -t target/"$TARGET"/release/build/mlua-sys-*/out/lib/liblua5.1.a | head -1)
cp "$LUA" target/"$TARGET"/release/liblua5.1.a
# Xcode does not see the library change: touch the C entry so the app relinks against it
touch "$SRCROOT/main.m"
