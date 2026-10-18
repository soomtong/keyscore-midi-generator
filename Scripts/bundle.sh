#!/bin/zsh
# KeyScore.app 번들 생성 (아이콘 포함): Scripts/bundle.sh → build/KeyScore.app
set -euo pipefail
cd "${0:A:h}/.."

swift build -c release
BIN=$(swift build -c release --show-bin-path)/KeyScore
APP=build/KeyScore.app
rm -rf "$APP" build/KeyScore.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/KeyScore"

"$BIN" --export-iconset build/KeyScore.iconset
iconutil -c icns build/KeyScore.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>KeyScore</string>
  <key>CFBundleDisplayName</key><string>KeyScore</string>
  <key>CFBundleIdentifier</key><string>dev.soomtong.keyscore</string>
  <key>CFBundleExecutable</key><string>KeyScore</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.3.0</string>
  <key>CFBundleVersion</key><string>3</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
</dict></plist>
PLIST

codesign --force --sign - "$APP"
echo "만든 위치: $APP"
