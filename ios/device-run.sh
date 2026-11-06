#!/bin/sh
# Build, install and launch nostalRE on a connected iPhone (unlocked, Developer Mode on), copy the twRO game
# files into the app's Documents (about 4 GB, first time only) and point it at Ragnarok Offline on this Mac.
# usage: ios/device-run.sh [--skip-data]   (env: DEVICE=iphone|ipad|<name>, GAME_DIR, MAC_IP)
set -e
cd "$(dirname "$0")"
BUNDLE=io.github.mikewong.nostalre
GAME_DIR="${GAME_DIR:-$HOME/.ragnarokoffline/twRO-client}"
MAC_IP="${MAC_IP:-$(ipconfig getifaddr en0 || ipconfig getifaddr en1)}"
DEV=$(xcrun devicectl list devices 2>/dev/null | grep -i "${DEVICE:-iphone}" | grep -oE '[0-9A-F-]{36}' | head -1 || true)
[ -n "$DEV" ] || { echo "no device matching "${DEVICE:-iphone}" found (plug in or same Wi-Fi, unlocked)"; exit 1; }
xcodegen generate -q
# build for this exact device so automatic signing registers it in the team's provisioning profile
UDID=$(xcrun devicectl device info details --device "$DEV" 2>/dev/null | awk '$2=="udid:"{print $3}')
xcodebuild -project nostalRE.xcodeproj -scheme nostalRE -configuration Release -destination "id=$UDID" \
  -derivedDataPath build -allowProvisioningUpdates -allowProvisioningDeviceRegistration build -quiet
xcrun devicectl device install app --device "$DEV" build/Build/Products/Release-iphoneos/nostalRE.app
copy() { xcrun devicectl device copy to --device "$DEV" --domain-type appDataContainer --domain-identifier "$BUNDLE" \
  --source "$1" --destination "Documents/$2" >/dev/null; }
if [ "$1" != "--skip-data" ]; then
  (cd "$GAME_DIR" && find event.grf data.grf data0.grf System BGM -type f) | while read -r f; do
    echo "copy $f"; copy "$GAME_DIR/$f" "$f"
  done
fi
TMP=$(mktemp -d)
printf '{ "login_servers": [ { "name": "Ragnarok Offline", "host": "%s", "port": 6900 } ],\n  "grf_paths": ["event.grf", "data.grf", "data0.grf"], "install_dir": ".", "bgm_path": "BGM", "text_encoding": "big5" }\n' "$MAC_IP" > "$TMP/config.json"
copy "$TMP/config.json" config.json
xcrun devicectl device process launch --device "$DEV" "$BUNDLE"
echo "launched; server $MAC_IP:6900"
