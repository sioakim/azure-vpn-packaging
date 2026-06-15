#!/usr/bin/env bash
#
# Package the Mac App Store "Azure VPN Client" into a portable .zip + .dmg
# so it can be installed on a machine that has no Mac App Store access
# (e.g. a Parallels macOS VM, which can't sign into the App Store).
#
# Why this works: the Azure VPN Client MAS binary is NOT FairPlay-encrypted
# (no LC_ENCRYPTION_INFO / cryptid), and it's validly Apple-signed, so the
# copied bundle passes Gatekeeper and runs as long as the app doesn't enforce
# strict App Store receipt validation at launch (it currently doesn't).
#
# Run this on the host Mac that installed Azure VPN Client from the App Store,
# AFTER an App Store update lands, to produce fresh artifacts.
#
# Usage:
#   ./package-azure-vpn.sh [OUTDIR] [--release]
#
#   OUTDIR     Where to write the artifacts (default: ~/Desktop).
#   --release  Also publish a GitHub release tagged with the app version,
#              uploading the .dmg as the asset (requires `gh` auth'd). The .zip
#              is still built locally for the build-your-own / verification path.

set -euo pipefail

APP="/Applications/Azure VPN Client.app"
OUTDIR="$HOME/Desktop"
DO_RELEASE=0

for arg in "$@"; do
  case "$arg" in
    --release) DO_RELEASE=1 ;;
    -*) echo "ERROR: unknown flag: $arg" >&2; exit 2 ;;
    *) OUTDIR="$arg" ;;
  esac
done

if [[ ! -d "$APP" ]]; then
  echo "ERROR: $APP not found. Install/update it from the Mac App Store first." >&2
  exit 1
fi

# Extract the real app version so artifacts + release are named after it.
VERSION="$(defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)"
BUILD="$(defaults read "$APP/Contents/Info" CFBundleVersion 2>/dev/null || true)"
if [[ -z "$VERSION" ]]; then
  echo "ERROR: could not read CFBundleShortVersionString from the bundle." >&2
  exit 1
fi
echo "==> Azure VPN Client version $VERSION (build ${BUILD:-?})"

mkdir -p "$OUTDIR"
ZIP="$OUTDIR/AzureVPNClient-$VERSION.zip"
DMG="$OUTDIR/AzureVPNClient-$VERSION.dmg"
TAG="v$VERSION"

echo "==> Source app:"
codesign -dvvv "$APP" 2>&1 | grep -E "Identifier|Format|Authority=Apple Mac OS|Runtime" || true

# Fail loud if the binary ever becomes FairPlay-encrypted (would break copy-to-VM).
if otool -l "$APP/Contents/MacOS/Azure VPN Client" 2>/dev/null | grep -q LC_ENCRYPTION_INFO; then
  echo "WARNING: binary now has LC_ENCRYPTION_INFO (FairPlay). Copy-to-VM will likely fail." >&2
fi

echo "==> Building zip (ditto preserves signature + symlinks)..."
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "==> Building dmg..."
rm -f "$DMG"
# hdiutil prints a benign 'Authentication error' for the root-owned bundle; ignore it.
hdiutil create -volname "Azure VPN Client $VERSION" -srcfolder "$APP" \
  -ov -format UDZO "$DMG" 2>/dev/null || true
[[ -f "$DMG" ]] || { echo "ERROR: DMG not created" >&2; exit 1; }

echo "==> Verifying zip round-trip signature..."
TMP="$(mktemp -d)"
ditto -x -k "$ZIP" "$TMP"
codesign --verify --deep --strict --verbose=2 "$TMP/Azure VPN Client.app"
spctl -a -vvv -t exec "$TMP/Azure VPN Client.app" 2>&1 | grep -E "accepted|source=" || true
rm -rf "$TMP"

echo
echo "==> Artifacts:"
ls -lh "$ZIP" "$DMG"

if [[ "$DO_RELEASE" -eq 1 ]]; then
  command -v gh >/dev/null || { echo "ERROR: --release needs the GitHub CLI (gh)." >&2; exit 1; }
  if gh release view "$TAG" >/dev/null 2>&1; then
    echo "==> Release $TAG already exists; uploading/clobbering DMG asset..."
    gh release upload "$TAG" "$DMG" --clobber
  else
    echo "==> Creating GitHub release $TAG..."
    gh release create "$TAG" "$DMG" \
      --title "Azure VPN Client $VERSION" \
      --notes "Repackaged Mac App Store **Azure VPN Client** $VERSION (build ${BUILD:-?}) for installation on Macs without App Store access (e.g. Parallels VMs).

Install: open the \`.dmg\`, drag to \`/Applications\`, then run:
\`\`\`
xattr -dr com.apple.quarantine \"/Applications/Azure VPN Client.app\"
\`\`\`
See the README for full rationale and the VPN-extension approval step.

The bundle remains Apple-signed (Team UBF8T346G9, Microsoft); this repackaging adds no code."
  fi
  echo "==> Released: $(gh release view "$TAG" --json url -q .url)"
fi
