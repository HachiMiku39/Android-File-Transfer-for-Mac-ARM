# Third-party components

The Swift UI and C bridge in this repository are MIT licensed. No Google Android
File Transfer binary, artwork, private framework or proprietary UI source is reused.

## libmtp 1.1.22

- Upstream: https://github.com/libmtp/libmtp
- Release: https://github.com/libmtp/libmtp/releases/tag/v1.1.22
- License: LGPL-2.1; upstream copyright notices are preserved in its source archive.
- Changes: `scripts/patch-mtp.py` selects a 1 MiB USB bulk buffer for SuperSpeed
  devices, preserves legacy iRiver buffers, and provides a 16 KiB compatibility mode.
- Archive SHA-256: `c3fcf411aea9cb9643590cbc9df99fa5fe30adcac695024442973d76fa5f87bc`.

## libusb 1.0.29

- Upstream: https://github.com/libusb/libusb
- License: LGPL-2.1-or-later; no source changes.
- Archive SHA-256: `5977fc950f8d1395ccea9bd48c06b3f808fd3c2c961b44b0c2e6e29fc3a70a85`.
- Configure uses `ac_cv_func_pipe2=no` to retain macOS 13 runtime support with
  newer SDKs, and a fixed libtool command-size cache value.

Both libraries are dynamically linked. `scripts/build-deps.sh` downloads the
exact corresponding upstream sources; the archives and complete LGPL texts are
also included in release source bundles. Users can build modified libraries and
replace the dylibs in `Contents/Frameworks`, then re-sign the app ad hoc with
`codesign --force --deep --sign - 'Android File Transfer ARM.app'`.

## Android SDK Platform Tools 37.0.1

- Official package: https://dl.google.com/android/repository/platform-tools_r37.0.1-darwin.zip
- Official documentation: https://developer.android.com/tools/releases/platform-tools
- Archive SHA-256: `ee39ad5967e95c2a07f04dbcbde96b1a0c916ba376096db5d2f498b7727a5d1d`.
- Bundled executables and helpers are the official Darwin tools with their
  Intel slices removed. No source code changes were made to these programs.
- All component copyright and license notices are distributed verbatim in
  `Contents/Resources/platform-tools/NOTICE.txt` and the app's `licenses` folder.
- AOSP source: https://android.googlesource.com/platform/packages/modules/adb/
  and https://android.googlesource.com/platform/system/core/+/main/fastboot/.

The MIT license for this project does not replace the licenses of these components.
