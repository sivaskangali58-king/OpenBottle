#!/bin/bash
# macOS-only: build a standalone SwiftUI .app wrapper and optional .dmg.
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "HATA: Bu betik macOS üzerinde, Xcode Command Line Tools ile çalışır."
  exit 1
fi

PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT"

if ! command -v swift >/dev/null; then
  echo "Swift bulunamadı. Xcode / Command Line Tools kur."
  exit 1
fi

echo "→ OpenBottle Release derleniyor..."
swift build --configuration release --product OpenBottle
BIN_DIR="$(swift build --configuration release --show-bin-path)"

OUT="$PROJECT/dist"
APP="$OUT/OpenBottle.app"
# Only remove old build products, never the user's Wine prefixes under Application Support.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/OpenBottle" "$APP/Contents/MacOS/OpenBottle"
cp "$PROJECT/scripts/steam-ui-fix.sh" "$APP/Contents/Resources/steam-ui-fix.sh"
cp "$PROJECT/scripts/steamwebhelper-wrapper.c" "$APP/Contents/Resources/steamwebhelper-wrapper.c"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleDevelopmentRegion</key><string>tr</string>
    <key>CFBundleExecutable</key><string>OpenBottle</string>
    <key>CFBundleIdentifier</key><string>org.openbottle.mac</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>OpenBottle</string>
    <key>CFBundleDisplayName</key><string>OpenBottle</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.8.9</string>
    <key>CFBundleVersion</key><string>19</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleIconFile</key><string>OpenBottle</string>
</dict></plist>
PLIST

ICON="$PROJECT/Assets/OpenBottleIcon.png"
if [[ -f "$ICON" ]]; then
  ICONSET="$OUT/OpenBottle.iconset"
  mkdir -p "$ICONSET"
  for px in 16 32 64 128 256 512; do
    sips -s format png -z "$px" "$px" "$ICON" --out "$ICONSET/icon_${px}x${px}.png" >/dev/null
  done
  cp "$ICONSET/icon_32x32.png" "$ICONSET/icon_16x16@2x.png"
  cp "$ICONSET/icon_64x64.png" "$ICONSET/icon_32x32@2x.png"
  cp "$ICONSET/icon_256x256.png" "$ICONSET/icon_128x128@2x.png"
  cp "$ICONSET/icon_512x512.png" "$ICONSET/icon_256x256@2x.png"
  cp "$ICON" "$ICONSET/icon_512x512@2x.png"
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/OpenBottle.icns"
  rm -rf "$ICONSET"
fi

echo "→ Yerel (ad-hoc) imzalama..."
codesign --force --sign - "$APP"

echo "→ DMG oluşturuluyor..."
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/OpenBottle.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "OpenBottle" -srcfolder "$STAGE" -format UDZO -ov "$OUT/OpenBottle-0.8.9.dmg"
rm -rf "$STAGE"

echo ""
echo "HAZIR: $APP"
echo "HAZIR: $OUT/OpenBottle-0.8.9.dmg"
echo "Not: DMG notarize edilmiş değildir; uygulama yalnızca güvenilir kaynak kodundan derlenmelidir."
