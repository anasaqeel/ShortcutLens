#!/bin/bash
# Builds the Swift package in release mode and packages it into a proper
# "Shortcut Lens.app" bundle: an .app is what LSUIElement, Accessibility
# permission prompts, and "Launch at Login" all expect to see, rather than a
# bare command-line binary.
#
#   ./Scripts/build_app.sh             build for this Mac, into dist/
#   ./Scripts/build_app.sh --install   ...and install into /Applications
#   ./Scripts/build_app.sh --release   build for distribution (see below);
#                                      used by make_dmg.sh
set -euo pipefail

cd "$(dirname "$0")/.."

INSTALL=false
RELEASE=false
for arg in "$@"; do
    case "${arg}" in
        --install) INSTALL=true ;;
        --release) RELEASE=true ;;
        *) echo "Unknown option: ${arg}" >&2; exit 64 ;;
    esac
done

if ${INSTALL} && ${RELEASE}; then
    echo "--release builds are for other people's Macs and are ad-hoc signed," >&2
    echo "so installing one here would lose your stable Accessibility grant." >&2
    echo "Use --install on its own for this Mac." >&2
    exit 64
fi

# The bundle carries the user-facing name; the executable and Swift module
# can't contain a space, so they use the compact form.
APP_NAME="Shortcut Lens"
EXECUTABLE="ShortcutLens"
APP_BUNDLE="dist/${APP_NAME}.app"

if ${RELEASE}; then
    # Universal, so the download also runs on Intel Macs.
    BUILD_FLAGS=(-c release --arch arm64 --arch x86_64)
else
    BUILD_FLAGS=(-c release)
fi

echo "==> Building release binary"
swift build "${BUILD_FLAGS[@]}"
# Ask SwiftPM where it put the products: single- and multi-architecture
# builds use different output directories.
BUILD_DIR="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"

echo "==> Assembling ${APP_BUNDLE}"
# Replace only the app bundle: dist/ also holds release disk images from
# make_dmg.sh, which an ordinary rebuild shouldn't wipe out.
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${EXECUTABLE}" "${APP_BUNDLE}/Contents/MacOS/${EXECUTABLE}"
cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

# Regenerate with: swift Scripts/make_icon.swift
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi

# Swift Package Manager's resource bundle (overrides.json etc.) must ship
# alongside the executable for Bundle.module to find it at runtime.
RESOURCE_BUNDLE="${BUILD_DIR}/${EXECUTABLE}_${EXECUTABLE}.bundle"
if [ -d "${RESOURCE_BUNDLE}" ]; then
    cp -R "${RESOURCE_BUNDLE}" "${APP_BUNDLE}/Contents/Resources/"
fi

# Prefer the stable local identity from Scripts/create_signing_identity.sh.
# Ad-hoc signatures derive the app's identity from the binary hash, so every
# rebuild looks like a new app to macOS and Accessibility access has to be
# granted all over again. A fixed certificate keeps that grant working.
SIGNING_IDENTITY="Shortcut Lens Local Signing"

if ${RELEASE}; then
    # Distribution builds are ad-hoc signed on purpose. The local certificate
    # is only trusted on the maintainer's Mac, so it wouldn't get past
    # Gatekeeper anywhere else either — it would just tie every release to
    # one machine. Ad-hoc is reproducible by anyone. (A Developer ID
    # certificate plus notarization is what removes the Gatekeeper warning.)
    echo "==> Ad-hoc code signing for distribution"
    codesign --force --deep --options runtime --sign - "${APP_BUNDLE}"
elif security find-identity -v -p codesigning | grep -q "${SIGNING_IDENTITY}"; then
    echo "==> Code signing as '${SIGNING_IDENTITY}'"
    codesign --force --deep --options runtime --sign "${SIGNING_IDENTITY}" "${APP_BUNDLE}"
else
    echo "==> Ad-hoc code signing (local use only)"
    echo "    Run ./Scripts/create_signing_identity.sh to stop having to"
    echo "    re-grant Accessibility access after every rebuild."
    codesign --force --deep --sign - "${APP_BUNDLE}"
fi

# A non-notarized app launched from an arbitrary folder gets App
# Translocation: macOS copies it to a randomized read-only path under
# /private/var/folders/.../AppTranslocation/<uuid>/ before running it. That
# path changes on every launch, so Accessibility permission granted to one
# run never applies to the next — the app appears to "keep asking" for
# access it was already given. Installing into /Applications avoids
# translocation entirely and gives TCC a stable identity to remember.
INSTALLED="/Applications/${APP_NAME}.app"
RUNNING_PATTERN="${APP_NAME}.app/Contents/MacOS/${EXECUTABLE}"

if ${INSTALL}; then
    echo "==> Installing to ${INSTALLED}"
    if pgrep -f "${RUNNING_PATTERN}" >/dev/null; then
        echo "    (quitting the running copy first)"
        pkill -f "${RUNNING_PATTERN}" || true
        sleep 1
    fi
    rm -rf "${INSTALLED}"
    cp -R "${APP_BUNDLE}" "${INSTALLED}"
    xattr -dr com.apple.quarantine "${INSTALLED}" 2>/dev/null || true
    echo "==> Done: ${INSTALLED}"
    # Launch by full path: 'open -a' can resolve to a stale LaunchServices
    # registration pointing back at dist/.
    echo "    Launch it with: open \"${INSTALLED}\""
elif ${RELEASE}; then
    echo "==> Done: ${APP_BUNDLE} (universal, ad-hoc signed)"
else
    echo "==> Done: ${APP_BUNDLE}"
    echo "    Run './Scripts/build_app.sh --install' to install into /Applications."
    echo "    Running it straight from dist/ triggers App Translocation, which"
    echo "    makes Accessibility permission fail to stick."
    echo "    Note: this signature is only valid on this Mac. To share the app,"
    echo "    use ./Scripts/make_dmg.sh instead."
fi
