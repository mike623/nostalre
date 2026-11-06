#!/bin/sh
# Archive nostalRE and upload it to App Store Connect / TestFlight.
# usage: ios/testflight.sh
# Auth: the Apple ID signed in to Xcode (Settings -> Accounts), or an App Store Connect API key via
#   ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (default ~/private_keys/AuthKey_$ASC_KEY_ID.p8).
# The app record for io.github.mikewong.nostalre must exist in App Store Connect before the first upload.
set -e
cd "$(dirname "$0")"
# ponytail: timestamp build number, always increasing, no state to keep
BUILD="${BUILD:-$(date -u +%Y%m%d%H%M)}"
ARCHIVE=build/nostalRE.xcarchive
AUTH=""
if [ -n "$ASC_KEY_ID" ] && [ -n "$ASC_ISSUER_ID" ]; then
  AUTH="-authenticationKeyID $ASC_KEY_ID -authenticationKeyIssuerID $ASC_ISSUER_ID -authenticationKeyPath ${ASC_KEY_PATH:-$HOME/private_keys/AuthKey_$ASC_KEY_ID.p8}"
fi
xcodegen generate -q
rm -rf "$ARCHIVE"
# shellcheck disable=SC2086
xcodebuild -project nostalRE.xcodeproj -scheme nostalRE -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates $AUTH CURRENT_PROJECT_VERSION="$BUILD" archive -quiet
cat > build/ExportOptions.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>Z6KK7N4RQ4</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
EOF
# shellcheck disable=SC2086
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist build/ExportOptions.plist \
  -exportPath build/export -allowProvisioningUpdates $AUTH
echo "uploaded build $BUILD; it shows in TestFlight after Apple finishes processing (~5-15 min)"
