#!/usr/bin/env swift
import AppKit
import Foundation

func color(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) -> NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

func rounded(_ rect: NSRect, radius: CGFloat, fill: NSColor) {
    fill.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func drawIcon(size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "NotchDeckIcon", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "cannot create icon canvas"])
    }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.shouldAntialias = true
    let scale = CGFloat(size) / 1024
    context.cgContext.scaleBy(x: scale, y: scale)

    let background = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896),
                                  xRadius: 200, yRadius: 200)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0, 0, 0, 0.22)
    shadow.shadowBlurRadius = 30
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.set()
    color(0.06, 0.075, 0.08).setFill()
    background.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0.16, 0.18, 0.19), ending: color(0.055, 0.065, 0.075))?
        .draw(in: background, angle: -90)

    let deckRect = NSRect(x: 178, y: 238, width: 668, height: 548)
    let deck = NSBezierPath(roundedRect: deckRect, xRadius: 94, yRadius: 94)
    NSGradient(starting: color(0.25, 0.28, 0.29), ending: color(0.13, 0.16, 0.17))?
        .draw(in: deck, angle: -90)
    color(1, 1, 1, 0.12).setStroke()
    deck.lineWidth = 2
    deck.stroke()

    // Чёрный вырез соединён с верхним краем карточки.
    rounded(NSRect(x: 338, y: 706, width: 348, height: 112), radius: 48,
            fill: color(0.075, 0.085, 0.095))
    rounded(NSRect(x: 432, y: 750, width: 122, height: 12), radius: 6,
            fill: color(0.21, 0.24, 0.25))
    color(0.6, 0.94, 0.8).setFill()
    NSBezierPath(ovalIn: NSRect(x: 575, y: 746, width: 20, height: 20)).fill()

    let mint = color(0.6, 0.94, 0.8)
    rounded(NSRect(x: 246, y: 418, width: 220, height: 220), radius: 48, fill: mint)
    for (index, height) in [48, 98, 142, 82, 44].enumerated() {
        rounded(NSRect(x: 281 + index * 31, y: 528 - height / 2, width: 15, height: height),
                radius: 7.5, fill: color(0.09, 0.24, 0.2))
    }
    rounded(NSRect(x: 512, y: 584, width: 210, height: 22), radius: 11,
            fill: color(0.86, 0.9, 0.88))
    rounded(NSRect(x: 512, y: 541, width: 152, height: 14), radius: 7,
            fill: color(0.51, 0.58, 0.57))

    mint.setFill()
    let play = NSBezierPath()
    play.move(to: NSPoint(x: 585, y: 438))
    play.line(to: NSPoint(x: 585, y: 492))
    play.line(to: NSPoint(x: 628, y: 465))
    play.close()
    play.fill()
    for origin in [514, 676] {
        rounded(NSRect(x: origin, y: 446, width: 8, height: 38), radius: 4,
                fill: color(0.65, 0.72, 0.7))
    }
    rounded(NSRect(x: 246, y: 332, width: 530, height: 14), radius: 7,
            fill: color(0.3, 0.35, 0.35))
    rounded(NSRect(x: 246, y: 332, width: 318, height: 14), radius: 7, fill: mint)
    color(0.87, 1, 0.94).setFill()
    NSBezierPath(ovalIn: NSRect(x: 551, y: 326, width: 26, height: 26)).fill()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "NotchDeckIcon", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "cannot encode icon PNG"])
    }
    return png
}

guard CommandLine.arguments.count == 2 else {
    fputs("usage: swift scripts/make-icon.swift <AppIcon.iconset>\n", stderr)
    exit(2)
}

do {
    let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let suffix = scale == 2 ? "@2x" : ""
            let name = "icon_\(points)x\(points)\(suffix).png"
            try drawIcon(size: points * scale).write(to: directory.appendingPathComponent(name))
        }
    }
} catch {
    fputs("icon: \(error.localizedDescription)\n", stderr)
    exit(1)
}
