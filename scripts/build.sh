#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
./scripts/build-deps.sh
# Stage outside cloud-synced folders: file providers may reattach FinderInfo
# during signing even immediately after xattr removal.
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/aft-arm-build.XXXXXX")"
APP="$STAGE/Android File Transfer ARM.app"
trap 'rm -rf "$STAGE"' EXIT
NATIVE="$ROOT/.build/native"
CACHE="${AFT_CACHE:-$ROOT/.build/deps}"
mkdir -p "$APP/Contents/"{MacOS,Frameworks,Resources/platform-tools,Resources/licenses} .build dist
clang -O2 -arch arm64 -mmacosx-version-min=13.0 -I"$NATIVE/include" -I"$NATIVE/include/libusb-1.0" \
  -c Sources/CMTP/Bridge.c -o .build/Bridge.o
swiftc -module-cache-path "$ROOT/.build/ModuleCache" -swift-version 5 -O -target arm64-apple-macosx13.0 \
  -import-objc-header Sources/CMTP/Bridge.h Sources/App/*.swift .build/Bridge.o \
  -L"$NATIVE/lib" -lmtp -lusb-1.0 -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -o "$APP/Contents/MacOS/Android File Transfer ARM"
cp "$NATIVE/lib/libmtp.9.dylib" "$APP/Contents/Frameworks/"
cp "$NATIVE/lib/libusb-1.0.0.dylib" "$APP/Contents/Frameworks/"
install_name_tool -id @rpath/libmtp.9.dylib "$APP/Contents/Frameworks/libmtp.9.dylib"
install_name_tool -id @rpath/libusb-1.0.0.dylib "$APP/Contents/Frameworks/libusb-1.0.0.dylib"
install_name_tool -change "$NATIVE/lib/libusb-1.0.0.dylib" @rpath/libusb-1.0.0.dylib "$APP/Contents/Frameworks/libmtp.9.dylib"
install_name_tool -change "$NATIVE/lib/libmtp.9.dylib" @rpath/libmtp.9.dylib "$APP/Contents/MacOS/Android File Transfer ARM"
install_name_tool -change "$NATIVE/lib/libusb-1.0.0.dylib" @rpath/libusb-1.0.0.dylib "$APP/Contents/MacOS/Android File Transfer ARM"
cp -R "$CACHE/platform-tools/." "$APP/Contents/Resources/platform-tools/"
# Remove Intel slices from every bundled Mach-O, including fastboot helpers.
while IFS= read -r -d '' f; do
  if file "$f" | grep -q 'Mach-O universal'; then
    lipo "$f" -thin arm64 -output "$f.arm64"
    chmod --reference="$f" "$f.arm64" 2>/dev/null || chmod 755 "$f.arm64"
    mv "$f.arm64" "$f"
  fi
done < <(find "$APP" -type f -print0)
cp .build/licenses/* "$APP/Contents/Resources/licenses/"
cp LICENSE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/licenses/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
xattr -cr "$APP"
# ad-hoc signature: Developer ID signing/notarization requires distributor credentials.
while IFS= read -r -d '' f; do
  if [[ "$f" != "$APP/Contents/MacOS/Android File Transfer ARM" ]] && file "$f" | grep -q 'Mach-O'; then codesign --force --sign - "$f"; fi
done < <(find "$APP" -type f -print0)
codesign --force --sign - "$APP"
./scripts/test.sh "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/dist/Android-File-Transfer-Mac-ARM.zip"
ditto --norsrc "$APP" "$ROOT/dist/Android File Transfer ARM.app"
shasum -a 256 "$ROOT/dist/Android-File-Transfer-Mac-ARM.zip" > "$ROOT/dist/SHA256SUMS.txt"
echo "Built: $ROOT/dist/Android File Transfer ARM.app"
