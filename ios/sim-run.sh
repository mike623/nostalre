#!/bin/sh
# Build, install and launch nostalRE on an iOS Simulator, with the twRO game files linked in (the
# Simulator shares the Mac's disk) and a config for Ragnarok Offline on this Mac.
# usage: ios/sim-run.sh [simulator name]   (env: GAME_DIR, RO_USER, RO_PASS, RO_CHAR_ID)
set -e
NAME="${1:-iPhone 17e}"
GAME_DIR="${GAME_DIR:-$HOME/.ragnarokoffline/twRO-client}"
BUNDLE=io.github.mikewong.nostalre
cd "$(dirname "$0")"
UDID=$(xcrun simctl list devices available | grep -F "$NAME (" | head -1 | grep -oE '[0-9A-F-]{36}' || true)
[ -n "$UDID" ] || UDID=$(xcrun simctl create "$NAME" "$NAME")
xcrun simctl boot "$UDID" 2>/dev/null || true
open -a Simulator
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcodegen generate -q
xcodebuild -project nostalRE.xcodeproj -scheme nostalRE -sdk iphonesimulator -configuration Release \
  -destination "id=$UDID" -derivedDataPath build CODE_SIGNING_ALLOWED=NO build -quiet
xcrun simctl install "$UDID" build/Build/Products/Release-iphonesimulator/nostalRE.app
DOCS="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)/Documents"
mkdir -p "$DOCS"
for f in event.grf data.grf data0.grf System BGM; do [ -e "$GAME_DIR/$f" ] && ln -sfn "$GAME_DIR/$f" "$DOCS/$f"; done
if [ ! -f "$DOCS/config.json" ]; then
  SOLO=""
  [ -n "$RO_USER" ] && SOLO=", \"solo\": { \"username\": \"$RO_USER\", \"password\": \"$RO_PASS\", \"char_id\": ${RO_CHAR_ID:-0} }"
  printf '{ "login_servers": [ { "name": "Ragnarok Offline", "host": "127.0.0.1", "port": 6900 } ],\n  "grf_paths": ["event.grf", "data.grf", "data0.grf"], "install_dir": ".", "bgm_path": "BGM", "text_encoding": "big5"%s }\n' "$SOLO" > "$DOCS/config.json"
fi
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
xcrun simctl launch "$UDID" "$BUNDLE"
echo "UDID=$UDID DOCS=$DOCS"
