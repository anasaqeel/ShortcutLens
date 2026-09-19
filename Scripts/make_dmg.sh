#!/bin/bash
# Packages Shortcut Lens as a downloadable disk image for people who'd rather
# not build it themselves:
#
#   ./Scripts/make_dmg.sh     ->  dist/ShortcutLens-<version>.dmg (+ .sha256)
#
# The disk image contains the app next to a shortcut to /Applications, so
# installing is a single drag. Upload both files to a GitHub release.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Shortcut Lens"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
DMG="dist/ShortcutLens-${VERSION}.dmg"

./Scripts/build_app.sh --release

STAGING="$(mktemp -d)"
trap 'rm -rf "${STAGING}"' EXIT

echo "==> Staging disk image contents"
cp -R "dist/${APP_NAME}.app" "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"

# Catch a broken bundle here rather than in a stranger's bug report.
codesign --verify --deep --strict "${STAGING}/${APP_NAME}.app"

echo "==> Creating ${DMG}"
rm -f "${DMG}" "${DMG}.sha256"
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${STAGING}" \
    -format UDZO \
    -ov \
    "${DMG}" >/dev/null
hdiutil verify "${DMG}" >/dev/null

# Published alongside the download so people can check that what they got is
# exactly what was released.
(cd dist && shasum -a 256 "$(basename "${DMG}")" > "$(basename "${DMG}").sha256")

echo "==> Done"
echo "    ${DMG} ($(du -h "${DMG}" | cut -f1 | tr -d ' '))"
echo "    SHA-256: $(cut -d' ' -f1 "${DMG}.sha256")"
echo
echo "    Publish it: on GitHub, Releases -> Draft a new release, create the"
echo "    tag v${VERSION}, and attach both ${DMG} and ${DMG}.sha256."
