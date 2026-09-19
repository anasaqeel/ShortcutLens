#!/bin/bash
# Builds the Swift package in release mode and packages it into a proper
# CheatSheet.app bundle: an .app is what LSUIElement, Accessibility
# permission prompts, and "Launch at Login" all expect to see, rather than a
# bare command-line binary.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="CheatSheet"
BUILD_DIR=".build/release"
APP_BUNDLE="dist/${APP_NAME}.app"

echo "==> Building release binary"
swift build -c release

echo "==> Assembling ${APP_BUNDLE}"
rm -rf "dist"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

# Regenerate with: swift Scripts/make_icon.swift
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi

# Swift Package Manager's resource bundle (overrides.json etc.) must ship
# alongside the executable for Bundle.module to find it at runtime.
RESOURCE_BUNDLE="${BUILD_DIR}/${APP_NAME}_${APP_NAME}.bundle"
if [ -d "${RESOURCE_BUNDLE}" ]; then
    cp -R "${RESOURCE_BUNDLE}" "${APP_BUNDLE}/Contents/Resources/"
fi

# Prefer the stable local identity from Scripts/create_signing_identity.sh.
# Ad-hoc signatures derive the app's identity from the binary hash, so every
# rebuild looks like a new app to macOS and Accessibility access has to be
# granted all over again. A fixed certificate keeps that grant working.
SIGNING_IDENTITY="CheatSheet Local Signing"

if security find-identity -v -p codesigning | grep -q "${SIGNING_IDENTITY}"; then
    echo "==> Code signing as '${SIGNING_IDENTITY}'"
    codesign --force --deep --options runtime --sign "${SIGNING_IDENTITY}" "${APP_BUNDLE}"
else
    echo "==> Ad-hoc code signing (local use only)"
    echo "    Run ./Scripts/create_signing_identity.sh to stop having to"
    echo "    re-grant Accessibility access after every rebuild."
    codesign --force --deep --sign - "${APP_BUNDLE}"
fi

# An ad-hoc signed app launched from an arbitrary folder gets App
# Translocation: macOS copies it to a randomized read-only path under
# /private/var/folders/.../AppTranslocation/<uuid>/ before running it. That
# path changes on every launch, so Accessibility permission granted to one
# run never applies to the next — the app appears to "keep asking" for
# access it was already given. Installing into /Applications avoids
# translocation entirely and gives TCC a stable identity to remember.
INSTALLED="/Applications/${APP_NAME}.app"

if [ "${1:-}" = "--install" ]; then
    echo "==> Installing to ${INSTALLED}"
    if pgrep -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" >/dev/null; then
        echo "    (quitting the running copy first)"
        pkill -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" || true
        sleep 1
    fi
    rm -rf "${INSTALLED}"
    cp -R "${APP_BUNDLE}" "${INSTALLED}"
    xattr -dr com.apple.quarantine "${INSTALLED}" 2>/dev/null || true
    echo "==> Done: ${INSTALLED}"
    # Launch by full path: 'open -a CheatSheet' can resolve to a stale
    # LaunchServices registration pointing back at dist/.
    echo "    Launch it with: open ${INSTALLED}"
else
    echo "==> Done: ${APP_BUNDLE}"
    echo "    Run './Scripts/build_app.sh --install' to install into /Applications."
    echo "    Running it straight from dist/ triggers App Translocation, which"
    echo "    makes Accessibility permission fail to stick."
fi

echo "    Note: this signature is only valid on this Mac. Sharing the app with"
echo "    anyone else needs a Developer ID certificate and notarization."
