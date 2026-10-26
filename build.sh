#!/bin/zsh
# Builds NotchUser.app (Apple Silicon + Intel, macOS 14+). Needs only the Xcode Command Line Tools.
#   ./build.sh           build and install into /Applications, then open it
#   ./build.sh release   build dist/NotchUser.zip to share (does not install)
set -e
cd "$(dirname "$0")"
VERSION=1.2.0
BUNDLE_ID=io.github.notchuser
MIN_MACOS=14.0

# Documents syncs with iCloud, which re-adds attributes codesign rejects,
# so the bundle is built and signed in a temp folder and copied out at the end.
TMP=$(mktemp -d)
APP=$TMP/NotchUser.app
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources

# One binary per architecture, glued together with lipo.
for ARCH in arm64 x86_64; do
  swiftc -O -swift-version 5 -parse-as-library -target $ARCH-apple-macos$MIN_MACOS \
    -o $TMP/NotchUser-$ARCH main.swift
done
lipo -create $TMP/NotchUser-arm64 $TMP/NotchUser-x86_64 -output $APP/Contents/MacOS/NotchUser

# Now Playing helper, loaded into /usr/bin/perl at runtime (see helper.m).
clang -O2 -dynamiclib -fobjc-arc -framework Foundation -arch arm64 -arch x86_64 -mmacosx-version-min=$MIN_MACOS \
  -o $APP/Contents/Resources/helper.dylib helper.m
codesign --force --sign - $APP/Contents/Resources/helper.dylib

# Icon: Assets/AppIcon.png (made from Assets/logo.png by Tools/make_icon.swift) -> AppIcon.icns.
[ -f Assets/AppIcon.png ] || swift Tools/make_icon.swift Assets/logo.png Assets/AppIcon.png
ICONSET=$TMP/AppIcon.iconset
mkdir -p $ICONSET
for S in 16 32 128 256 512; do
  sips -z $S $S Assets/AppIcon.png --out $ICONSET/icon_${S}x${S}.png >/dev/null
  sips -z $((S * 2)) $((S * 2)) Assets/AppIcon.png --out $ICONSET/icon_${S}x${S}@2x.png >/dev/null
done
iconutil -c icns $ICONSET -o $APP/Contents/Resources/AppIcon.icns

cat > $APP/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>NotchUser</string>
  <key>CFBundleDisplayName</key><string>NotchUser</string>
  <key>CFBundleExecutable</key><string>NotchUser</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Para mostrar e controlar a música do Spotify e do Apple Music.</string>
</dict></plist>
EOF
codesign --force --sign - $APP

if [ "${1:-}" = "release" ]; then
  mkdir -p dist
  rm -f dist/NotchUser.zip
  ditto -c -k --norsrc --keepParent $APP dist/NotchUser.zip
  rm -rf $TMP
  echo "ok: $(pwd)/dist/NotchUser.zip"
  exit 0
fi

# Installs straight into /Applications so there is only ever one copy running.
pkill -x NotchUser || true
pkill -x NotchPlayer || true  # the app's old name
rm -rf NotchUser.app /Applications/NotchUser.app
ditto --norsrc $APP /Applications/NotchUser.app
rm -rf $TMP
open /Applications/NotchUser.app
echo "ok: /Applications/NotchUser.app"
