#!/bin/bash
# Builds a universal (Apple Silicon + Intel) build/Platter.app, ad-hoc signed.
# With --dist, also packages dist/Platter-<version>.dmg and .zip for distribution outside the App Store.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
ARCHS=(--arch arm64 --arch x86_64)

swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/Platter"
APP=build/Platter.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Platter"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# App icon, rendered by the app itself.
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
"$BIN" --icon build/icon-1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$APP"
echo "Built $APP ($VERSION, $(lipo -archs "$APP/Contents/MacOS/Platter"))"

if [[ "${1:-}" == "--dist" ]]; then
  rm -rf dist && mkdir -p dist
  ditto -c -k --keepParent "$APP" "dist/Platter-$VERSION.zip"
  STAGE=$(mktemp -d)
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "Platter" -srcfolder "$STAGE" -ov -format UDZO "dist/Platter-$VERSION.dmg" >/dev/null
  rm -rf "$STAGE"
  echo "Packaged dist/Platter-$VERSION.dmg and dist/Platter-$VERSION.zip"
fi
