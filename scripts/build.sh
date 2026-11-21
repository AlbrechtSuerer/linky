#!/bin/zsh
# Builds Linky.app into ./build.
#   --install  also copies it to /Applications and starts it
#   --zip      also creates build/Linky.zip for a GitHub release
set -euo pipefail
cd "${0:A:h}/.."

APP=build/Linky.app
ICNS=Resources/AppIcon.icns

# App icon (only rendered once)
if [[ ! -f $ICNS ]]; then
  echo "› Icon"
  TMP=$(mktemp -d)
  swift scripts/make-icon.swift "$TMP/icon.png"
  ICONSET="$TMP/AppIcon.iconset"; mkdir "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$TMP/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$TMP/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o $ICNS
  rm -rf "$TMP"
fi

echo "› Compiling"
swift build -c release

echo "› App bundle"
rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp .build/release/Linky $APP/Contents/MacOS/Linky
cp Resources/Info.plist $APP/Contents/Info.plist
cp $ICNS $APP/Contents/Resources/AppIcon.icns
codesign --force --sign - $APP

if [[ " $* " == *" --zip "* ]]; then
  echo "› Zipping"
  rm -f build/Linky.zip
  ditto -c -k --keepParent $APP build/Linky.zip
fi

if [[ " $* " == *" --install "* ]]; then
  echo "› Installing to /Applications"
  pkill -x Linky 2>/dev/null || true
  sleep 0.5
  rm -rf /Applications/Linky.app
  cp -R $APP /Applications/Linky.app
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Linky.app
  /System/Library/CoreServices/pbs -update
  open /Applications/Linky.app
fi

echo "✓ Done"
