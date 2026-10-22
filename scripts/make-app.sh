#!/bin/zsh
# Builds dist/Trihedron.app.  Pass --install to also copy it to /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="dist/Trihedron.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Trihedron "$APP/Contents/MacOS/Trihedron"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Trihedron</string>
  <key>CFBundleDisplayName</key><string>Trihedron</string>
  <key>CFBundleIdentifier</key><string>com.chancellor.trihedron</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleExecutable</key><string>Trihedron</string>
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
  rm -rf /Applications/Trihedron.app
  ditto "$APP" /Applications/Trihedron.app
  echo "installed /Applications/Trihedron.app"
fi
