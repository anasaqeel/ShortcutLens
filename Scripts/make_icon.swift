#!/usr/bin/env swift
//
// Draws the app icon and writes Resources/AppIcon.icns.
//
// Run with:  swift Scripts/make_icon.swift
//
// The artwork is generated rather than hand-drawn so it can be tweaked in
// one place and regenerated at every size macOS asks for.

import AppKit
import Foundation

let iconSizes = [16, 32, 64, 128, 256, 512, 1024]

/// Draws the icon at `size` points square.
func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    guard let context = NSGraphicsContext.current?.cgContext else { return image }
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    // macOS icons leave a margin around the artwork rather than bleeding to
    // the edge, so the rounded square matches other icons in the Dock.
    let inset = size * 0.08
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let cornerRadius = rect.width * 0.2237 // Apple's squircle-ish ratio
    let shape = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.38, green: 0.40, blue: 0.95, alpha: 1.0),
        NSColor(calibratedRed: 0.22, green: 0.24, blue: 0.70, alpha: 1.0)
    ])
    gradient?.draw(in: shape, angle: -90)

    // A hairline edge keeps the icon from dissolving into a dark Dock.
    shape.lineWidth = max(1, size * 0.004)
    NSColor(white: 1, alpha: 0.18).setStroke()
    shape.stroke()

    // Below roughly 64pt the caption is illegible, so the glyph gets the
    // whole canvas instead of a smudge of text under it.
    let showsCaption = size >= 64

    let glyphSize = showsCaption ? rect.height * 0.46 : rect.height * 0.62
    let glyph = "\u{2318}"
    let glyphAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: glyphSize, weight: .medium),
        .foregroundColor: NSColor.white
    ]
    let glyphSizeDrawn = glyph.size(withAttributes: glyphAttributes)
    let glyphOrigin = NSPoint(
        x: rect.midX - glyphSizeDrawn.width / 2,
        y: showsCaption
            ? rect.midY - glyphSizeDrawn.height / 2 + rect.height * 0.10
            : rect.midY - glyphSizeDrawn.height / 2
    )
    glyph.draw(at: glyphOrigin, withAttributes: glyphAttributes)

    if showsCaption {
        let caption = "CheatSheet"
        let captionSize = rect.height * 0.135
        let captionAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: captionSize, weight: .semibold),
            .foregroundColor: NSColor(white: 1, alpha: 0.95),
            .kern: captionSize * 0.01
        ]
        let captionDrawn = caption.size(withAttributes: captionAttributes)
        let captionOrigin = NSPoint(
            x: rect.midX - captionDrawn.width / 2,
            y: rect.minY + rect.height * 0.13
        )
        caption.draw(at: captionOrigin, withAttributes: captionAttributes)
    }

    return image
}

func pngData(for image: NSImage, pixelSize: Int) -> Data? {
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }
    representation.size = NSSize(width: pixelSize, height: pixelSize)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
    image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
    NSGraphicsContext.restoreGraphicsState()

    return representation.representation(using: .png, properties: [:])
}

// MARK: - Write the iconset

let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconsetURL = projectRoot.appendingPathComponent("build/AppIcon.iconset")
let outputURL = projectRoot.appendingPathComponent("Resources/AppIcon.icns")

try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

// iconutil expects each size at 1x and 2x.
for size in iconSizes where size <= 512 {
    for scale in [1, 2] {
        let pixels = size * scale
        guard pixels <= 1024 else { continue }
        let image = drawIcon(size: CGFloat(pixels))
        guard let data = pngData(for: image, pixelSize: pixels) else { continue }
        let suffix = scale == 2 ? "@2x" : ""
        let name = "icon_\(size)x\(size)\(suffix).png"
        try data.write(to: iconsetURL.appendingPathComponent(name))
    }
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil failed\n".utf8))
    exit(1)
}

try? FileManager.default.removeItem(at: iconsetURL)
print("Wrote \(outputURL.path)")
