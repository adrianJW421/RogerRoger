#!/usr/bin/env bash
# Publishable build: only committed source enters the clean staging directory.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-0.4.1}"
BUILD_NUMBER="${BUILD_NUMBER:-10.8}"
SOURCE_COMMIT="$(git -C "$ROOT" rev-parse "${SOURCE_COMMIT:-HEAD}^{commit}")"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/rogerroger-release.XXXXXX")"
WORK="$(cd "$WORK" && pwd -P)"
trap 'if [ -d "$WORK/mounted" ]; then hdiutil detach "$WORK/mounted" >/dev/null 2>&1 || true; fi; rm -rf "$WORK"' EXIT
mkdir -p "$WORK/source" "$WORK/image" "$ROOT/dist"
git -C "$ROOT" archive "$SOURCE_COMMIT" | tar -xf - -C "$WORK/source"
python3 - "$WORK/source" <<'CHECK'
from pathlib import Path
import sys
root=Path(sys.argv[1])
for p in root.rglob('*'):
    assert p.name.lower() != 'handoff.md', 'Local handoff must never enter a release'
    assert p.name != '.local' and p.suffix not in ('.keystore', '.jks', '.p12'), 'Private file in source archive'
CHECK
( cd "$WORK/source/web" && npm ci --no-audit --no-fund )
mkdir -p "$WORK/module-cache"
( cd "$WORK/source" && VERSION="$VERSION" BUILD_NUMBER="$BUILD_NUMBER" SWIFT_ARCHS="arm64 x86_64" \
  CLANG_MODULE_CACHE_PATH="$WORK/module-cache" SWIFTPM_MODULECACHE_OVERRIDE="$WORK/module-cache" \
  bash scripts/build_app.sh )
ditto --norsrc --noextattr --noqtn --noacl "$WORK/source/dist/RogerRoger.app" "$WORK/image/RogerRoger.app"
ln -s /Applications "$WORK/image/Applications"
python3 - "$WORK/image/RogerRoger.app" "$ROOT" <<'CHECK'
from pathlib import Path
import sys
app=Path(sys.argv[1])
markers=[str(Path(sys.argv[2]).resolve()).encode(), str(Path.home()).encode()]
for p in app.rglob('*'):
    if p.is_symlink() or not p.is_file(): continue
    assert p.name.lower() != 'handoff.md' and '.local' not in p.parts
    assert p.suffix not in ('.keystore','.jks','.p12')
    assert not any(marker in p.read_bytes() for marker in markers), 'Private build path in '+str(p.relative_to(app))
CHECK
DMG="$ROOT/dist/RogerRoger-$VERSION-macos-universal.dmg"
hdiutil create -ov -volname RogerRoger -srcfolder "$WORK/image" -fs HFS+ -format UDZO "$DMG"
hdiutil verify "$DMG"
mkdir -p "$WORK/mounted"
hdiutil attach -readonly -nobrowse -mountpoint "$WORK/mounted" "$DMG" >/dev/null
codesign --verify --deep --strict "$WORK/mounted/RogerRoger.app"
lipo "$WORK/mounted/RogerRoger.app/Contents/MacOS/VibeCast" -verify_arch arm64 x86_64
[ "$(readlink "$WORK/mounted/Applications")" = /Applications ]
hdiutil detach "$WORK/mounted" >/dev/null
rmdir "$WORK/mounted"
echo "Verified DMG: $DMG"
shasum -a 256 "$DMG"
