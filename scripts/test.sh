#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APP="${1:-$ROOT/dist/Android File Transfer ARM.app}"
mkdir -p .build
swiftc -module-cache-path "$ROOT/.build/ModuleCache" -swift-version 5 Sources/App/Core.swift Tests/main.swift -o .build/core-tests
.build/core-tests
python3 - "$APP" <<'PY'
import pathlib, subprocess, sys
app = pathlib.Path(sys.argv[1])
count = 0
for p in app.rglob('*'):
    if not p.is_file(): continue
    kind = subprocess.check_output(['file', '-b', str(p)], text=True)
    if 'Mach-O' not in kind: continue
    arch = subprocess.check_output(['lipo', '-archs', str(p)], text=True).strip()
    assert arch == 'arm64', (p, arch)
    dependencies = subprocess.check_output(['otool', '-L', str(p)], text=True)
    assert '/opt/homebrew' not in dependencies and '/.build/' not in dependencies, dependencies
    count += 1
assert count >= 5, count
print(f'PASS: {count} bundled Mach-O files are arm64; no build-machine dylib paths')
PY
codesign --verify --deep --strict "$APP"
"$APP/Contents/Resources/platform-tools/adb" version
"$APP/Contents/Resources/platform-tools/fastboot" --version
"$APP/Contents/MacOS/Android File Transfer ARM" --mtp-probe
