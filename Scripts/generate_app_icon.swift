#!/usr/bin/env swift

import AppKit
import Foundation

struct IconSpec {
    let filename: String
    let pixels: Int
}

let specs: [IconSpec] = [
    .init(filename: "icon_16x16.png", pixels: 16),
    .init(filename: "icon_16x16@2x.png", pixels: 32),
    .init(filename: "icon_32x32.png", pixels: 32),
    .init(filename: "icon_32x32@2x.png", pixels: 64),
    .init(filename: "icon_128x128.png", pixels: 128),
    .init(filename: "icon_128x128@2x.png", pixels: 256),
    .init(filename: "icon_256x256.png", pixels: 256),
    .init(filename: "icon_256x256@2x.png", pixels: 512),
    .init(filename: "icon_512x512.png", pixels: 512),
    .init(filename: "icon_512x512@2x.png", pixels: 1024)
]

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: \(CommandLine.arguments[0]) <iconset-dir> [preview-png]\n", stderr)
    exit(1)
}

let iconsetURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let previewURL = CommandLine.arguments.count > 2 ? URL(fileURLWithPath: CommandLine.arguments[2]) : nil
let fileManager = FileManager.default

try? fileManager.removeItem(at: iconsetURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let cardColor = NSColor(calibratedRed: 0.95, green: 0.93, blue: 0.90, alpha: 1)
let borderColor = NSColor(calibratedWhite: 0.0, alpha: 0.08)
let markColor = NSColor(calibratedRed: 0.06, green: 0.09, blue: 0.16, alpha: 1)

func drawIcon(in rect: CGRect) {
    let size = min(rect.width, rect.height)
    let inset = size * 0.08
    let iconRect = rect.insetBy(dx: inset, dy: inset)
    let cornerRadius = size * 0.23

    let base = NSBezierPath(roundedRect: iconRect, xRadius: cornerRadius, yRadius: cornerRadius)
    cardColor.setFill()
    base.fill()
    borderColor.setStroke()
    base.lineWidth = max(2, size * 0.012)
    base.stroke()

    let markRect = CGRect(
        x: rect.minX + size * 0.18,
        y: rect.minY + size * 0.18,
        width: size * 0.64,
        height: size * 0.64
    )

    let ring = NSBezierPath(ovalIn: markRect)
    markColor.setStroke()
    ring.lineWidth = size * (1.3 / 18.0)
    ring.stroke()

    let barSpecs: [(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat)] = [
        (5.55, 7.357, 1.6, 3.285),
        (8.55, 6.08, 1.6, 5.84),
        (11.55, 7.357, 1.6, 3.285)
    ]

    markColor.setFill()
    for spec in barSpecs {
        let barRect = CGRect(
            x: rect.minX + size * (spec.x / 18.0),
            y: rect.minY + size * (spec.y / 18.0),
            width: size * (spec.w / 18.0),
            height: size * (spec.h / 18.0)
        )
        let corner = size * (0.9 / 18.0)
        let bar = NSBezierPath(roundedRect: barRect, xRadius: corner, yRadius: corner)
        bar.fill()
    }
}

func pngData(pixelSize: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixelSize, height: pixelSize)

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    context.imageInterpolation = .high
    NSGraphicsContext.current = context
    NSColor.clear.setFill()
    NSBezierPath(rect: CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize)).fill()
    drawIcon(in: CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])!
}

for spec in specs {
    let outputURL = iconsetURL.appendingPathComponent(spec.filename)
    try pngData(pixelSize: spec.pixels).write(to: outputURL)
}

if let previewURL {
    try pngData(pixelSize: 1024).write(to: previewURL)
}
