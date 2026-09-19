#!/usr/bin/env swift
//
// Draws the app icon and writes Resources/AppIcon.icns.
//
// Run with:  swift Scripts/make_icon.swift
//
// A ⌘ seen through a magnifying glass — a lens on your shortcuts. The artwork
// is generated rather than hand-drawn so it can be tweaked in one place and
// regenerated at every size macOS asks for.

import AppKit
import CoreText
import Foundation

/// The ⌘ glyph's outline, so it can be positioned by its true geometric
/// bounds. Drawing it as text would centre the font's line box instead,
/// which includes ascender/descender space and sits visibly off-centre.
func commandGlyphPath() -> CGPath? {
    let font = NSFont.systemFont(ofSize: 100, weight: .semibold) as CTFont
    var characters = Array("\u{2318}".utf16)
    var glyphs = [CGGlyph](repeating: 0, count: characters.count)
    guard CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count) else { return nil }
    return CTFontCreatePathForGlyph(font, glyphs[0], nil)
}

func point(from center: CGPoint, distance: CGFloat, angle: CGFloat) -> CGPoint {
    CGPoint(x: center.x + distance * cos(angle), y: center.y + distance * sin(angle))
}

/// Draws the icon on a canvas `size` pixels square.
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
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let width = rect.width
    let cornerRadius = width * 0.2237
    let background = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

    NSGradient(colors: [
        NSColor(calibratedRed: 0.38, green: 0.40, blue: 0.95, alpha: 1.0),
        NSColor(calibratedRed: 0.22, green: 0.24, blue: 0.70, alpha: 1.0)
    ])?.draw(in: background, angle: -90)

    // A hairline edge keeps the icon from dissolving into a dark Dock.
    background.lineWidth = max(1, size * 0.004)
    NSColor(white: 1, alpha: 0.18).setStroke()
    background.stroke()

    // At the smallest sizes fine detail turns to mush, so strokes thicken
    // and the glass highlight is dropped.
    let isTiny = size < 48

    // The lens sits up and to the left so the handle can run to the
    // bottom-right corner, keeping the whole mark visually centred.
    let lensCenter = CGPoint(x: rect.minX + width * 0.43, y: rect.minY + width * 0.57)
    let lensRadius = width * 0.28
    let ringWidth = width * (isTiny ? 0.085 : 0.06)
    let innerRadius = lensRadius - ringWidth / 2
    let handleAngle = -CGFloat.pi / 4 // towards the bottom-right

    // Glass: a faint fill so the lens reads as a lens, not just a ring.
    let glass = CGRect(
        x: lensCenter.x - innerRadius, y: lensCenter.y - innerRadius,
        width: innerRadius * 2, height: innerRadius * 2
    )
    context.setFillColor(NSColor(white: 1, alpha: 0.14).cgColor)
    context.fillEllipse(in: glass)

    // The ⌘, scaled to sit comfortably inside the glass.
    if let glyph = commandGlyphPath() {
        let bounds = glyph.boundingBoxOfPath
        let target = innerRadius * 1.12
        let scale = target / max(bounds.width, bounds.height)
        var transform = CGAffineTransform.identity
            .translatedBy(x: lensCenter.x, y: lensCenter.y)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -bounds.midX, y: -bounds.midY)
        if let placed = glyph.copy(using: &transform) {
            context.addPath(placed)
            context.setFillColor(NSColor.white.cgColor)
            context.fillPath()
        }
    }

    context.setStrokeColor(NSColor.white.cgColor)
    context.setLineCap(.round)

    // Ring.
    context.setLineWidth(ringWidth)
    context.strokeEllipse(in: CGRect(
        x: lensCenter.x - lensRadius, y: lensCenter.y - lensRadius,
        width: lensRadius * 2, height: lensRadius * 2
    ))

    // Handle — starts on the ring's centreline so its round cap merges into
    // the ring rather than leaving a seam.
    let handleStart = point(from: lensCenter, distance: lensRadius, angle: handleAngle)
    let handleEnd = point(from: lensCenter, distance: lensRadius + width * 0.27, angle: handleAngle)
    context.setLineWidth(width * (isTiny ? 0.11 : 0.09))
    context.move(to: handleStart)
    context.addLine(to: handleEnd)
    context.strokePath()

    // A soft highlight on the glass's upper-left edge.
    if !isTiny {
        context.setStrokeColor(NSColor(white: 1, alpha: 0.45).cgColor)
        context.setLineWidth(width * 0.022)
        context.addArc(
            center: lensCenter,
            radius: innerRadius * 0.78,
            startAngle: CGFloat.pi * 0.62,
            endAngle: CGFloat.pi * 0.88,
            clockwise: false
        )
        context.strokePath()
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

// The standard iconset: each size at 1x and 2x.
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        guard let data = pngData(for: drawIcon(size: CGFloat(pixels)), pixelSize: pixels) else { continue }
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: iconsetURL.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
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

// GitHub can't render .icns, so the README shows this PNG instead. Written
// from the same drawing code so the two can't drift apart.
let previewURL = projectRoot.appendingPathComponent("docs/icon.png")
try FileManager.default.createDirectory(
    at: previewURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
if let preview = pngData(for: drawIcon(size: 256), pixelSize: 256) {
    try preview.write(to: previewURL)
    print("Wrote \(previewURL.path)")
}
