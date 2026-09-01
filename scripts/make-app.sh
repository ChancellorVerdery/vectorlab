#!/bin/zsh
# Builds dist/VectorLab.app.  Pass --install to also copy it to /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="dist/VectorLab.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/VectorLab "$APP/Contents/MacOS/VectorLab"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>VectorLab</string>
  <key>CFBundleDisplayName</key><string>VectorLab</string>
  <key>CFBundleIdentifier</key><string>com.chancellor.vectorlab</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleExecutable</key><string>VectorLab</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "built $APP"

if [ "${1:-}" = "--install" ]; then
  rm -rf /Applications/VectorLab.app
  ditto "$APP" /Applications/VectorLab.app
  echo "installed /Applications/VectorLab.app"
fi
