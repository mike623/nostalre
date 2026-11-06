#!/bin/sh
# Wrap the release binary in nostalRE.app. The client reads config.json etc. from its working
# directory, so the launcher runs it from ~/Library/Application Support/nostalRE (seeded from
# config.sample.json on first launch). Put GRFs there or point grf_paths at them in config.json.
# usage: macos/bundle.sh [path/to/nostalre-client] [version]
set -e
cd "$(dirname "$0")/.."
BIN="${1:-target/release/nostalre-client}"
VERSION="${2:-0.1.0}"
APP=target/nostalRE.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/nostalre-client"
cp config.sample.json "$APP/Contents/Resources/"
iconutil_src=ios/Assets.xcassets/AppIcon.appiconset/icon-1024.png
if [ -f "$iconutil_src" ]; then
  set_dir=$(mktemp -d)/AppIcon.iconset; mkdir -p "$set_dir"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$iconutil_src" --out "$set_dir/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$iconutil_src" --out "$set_dir/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$set_dir" -o "$APP/Contents/Resources/AppIcon.icns"
fi
cat > "$APP/Contents/MacOS/nostalRE" <<'EOF'
#!/bin/sh
DIR="$HOME/Library/Application Support/nostalRE"
RES="$(cd "$(dirname "$0")/../Resources" && pwd)"
mkdir -p "$DIR" && cd "$DIR"
[ -f config.json ] || cp "$RES/config.sample.json" config.json
exec "$(dirname "$0")/nostalre-client" >> "$DIR/nostalre.log" 2>&1
EOF
chmod +x "$APP/Contents/MacOS/nostalRE"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>nostalRE</string>
  <key>CFBundleDisplayName</key><string>nostalRE</string>
  <key>CFBundleIdentifier</key><string>io.github.mikewong.nostalre.mac</string>
  <key>CFBundleExecutable</key><string>nostalRE</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSLocalNetworkUsageDescription</key><string>Connects to the Ragnarok server on your local network.</string>
</dict></plist>
EOF
# ponytail: ad-hoc signature only; add Developer ID signing + notarization when sharing builds beyond yourself
codesign --force --deep --sign - "$APP"
echo "$APP"
