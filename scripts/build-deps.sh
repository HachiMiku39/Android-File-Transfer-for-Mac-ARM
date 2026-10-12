#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${AFT_CACHE:-$ROOT/.build/deps}"
PREFIX="$ROOT/.build/native"
mkdir -p "$CACHE" "$PREFIX"
fetch() {
  local url="$1" file="$2" sha="$3"
  if [[ ! -f "$CACHE/$file" ]]; then
    curl --fail --location --retry 3 --connect-timeout 20 --max-time 180 \
      -H 'Accept: application/octet-stream' "$url" -o "$CACHE/$file"
  fi
  echo "$sha  $CACHE/$file" | shasum -a 256 -c -
}
fetch https://api.github.com/repos/libusb/libusb/releases/assets/259998533 libusb-1.0.29.tar.bz2 5977fc950f8d1395ccea9bd48c06b3f808fd3c2c961b44b0c2e6e29fc3a70a85
fetch https://api.github.com/repos/libmtp/libmtp/releases/assets/207830064 libmtp-1.1.22.tar.gz c3fcf411aea9cb9643590cbc9df99fa5fe30adcac695024442973d76fa5f87bc
fetch https://dl.google.com/android/repository/platform-tools_r37.0.1-darwin.zip platform-tools.zip ee39ad5967e95c2a07f04dbcbde96b1a0c916ba376096db5d2f498b7727a5d1d
export MACOSX_DEPLOYMENT_TARGET=13.0
export CFLAGS='-O2 -arch arm64 -mmacosx-version-min=13.0'
export LDFLAGS='-arch arm64 -mmacosx-version-min=13.0'
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
# Modern macOS SDKs expose pipe2, but it is unavailable on our macOS 13 target.
export ac_cv_func_pipe2=no
# Keep older release libtool's command-size probe stable on recent macOS.
export lt_cv_sys_max_cmd_len=262144
JOBS="${AFT_JOBS:-8}"
if [[ ! -f "$PREFIX/lib/libusb-1.0.dylib" ]]; then
  tar xf "$CACHE/libusb-1.0.29.tar.bz2" -C "$CACHE"
  (cd "$CACHE/libusb-1.0.29"; ./configure --prefix="$PREFIX" --disable-static --enable-shared; make -j"$JOBS"; make install)
fi
if [[ ! -f "$PREFIX/lib/libmtp.dylib" ]]; then
  tar xf "$CACHE/libmtp-1.1.22.tar.gz" -C "$CACHE"
  python3 "$ROOT/scripts/patch-mtp.py" "$CACHE/libmtp-1.1.22/src/libusb1-glue.c"
  (cd "$CACHE/libmtp-1.1.22"; ./configure --prefix="$PREFIX" --disable-static --enable-shared --disable-mtpz --disable-doxygen; make -j"$JOBS"; make install)
fi
if [[ ! -f "$CACHE/platform-tools/adb" ]]; then unzip -q "$CACHE/platform-tools.zip" -d "$CACHE"; fi
mkdir -p "$ROOT/.build/licenses"
cp "$CACHE/libusb-1.0.29/COPYING" "$ROOT/.build/licenses/libusb-LGPL-2.1.txt"
cp "$CACHE/libmtp-1.1.22/COPYING" "$ROOT/.build/licenses/libmtp-LGPL-2.1.txt"
cp "$CACHE/platform-tools/NOTICE.txt" "$ROOT/.build/licenses/Android-platform-tools-NOTICE.txt"
echo "Native dependencies ready: $PREFIX"
