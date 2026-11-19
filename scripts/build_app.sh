#!/bin/zsh
# Builds Yoman.app (release), ad-hoc signs it, and installs it to ~/Applications.
#   scripts/build_app.sh            build + install
#   scripts/build_app.sh --no-install
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release 2>&1 | grep -v "ld: warning" || true
BIN=$(swift build -c release --show-bin-path)

APP=dist/Yoman.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/characters"
cp "$BIN/Yoman" "$APP/Contents/MacOS/Yoman"
cp "$BIN/yoman-bridge" "$APP/Contents/MacOS/yoman-bridge"
cp -R Assets/cat "$APP/Contents/Resources/characters/cat"
cp -R Assets/sounds "$APP/Contents/Resources/sounds"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Yoman</string>
  <key>CFBundleDisplayName</key><string>Yoman Companion</string>
  <key>CFBundleIdentifier</key><string>dev.yoman.companion</string>
  <key>CFBundleExecutable</key><string>Yoman</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# A fixed designated requirement (bundle id) instead of the default cdhash, so macOS keeps the
# Accessibility grant across rebuilds. Fine for a personal, locally built app.
codesign --force --sign - -r='designated => identifier "dev.yoman.bridge"' "$APP/Contents/MacOS/yoman-bridge"
codesign --force --sign - -r='designated => identifier "dev.yoman.companion"' "$APP"
echo "Built $APP"

if [[ "${1:-}" != "--no-install" ]]; then
  mkdir -p ~/Applications
  pkill -x Yoman 2>/dev/null && sleep 0.5 || true
  rm -rf ~/Applications/Yoman.app
  cp -R "$APP" ~/Applications/Yoman.app
  echo "Installed ~/Applications/Yoman.app"
fi
