#!/usr/bin/env swift

// Renders Resources/AppIcon.icns: a graphite squircle carrying three
// concentric white usage rings. Run with `swift scripts/make-icon.swift`.

import AppKit
import Foundation

enum IconGeometry {
    /// Fraction of the canvas the squircle occupies, leaving the margin macOS
    /// expects around an app icon.
    static let squircleScale: CGFloat = 0.82
    /// Superellipse exponent. Higher is squarer; 5 approximates Apple's shape.
    static let squircleExponent: CGFloat = 5

    static let outerRadius: CGFloat = 0.30
    static let ringWidth: CGFloat = 0.055
    static let ringGap: CGFloat = 0.045
    /// Outer to inner: Cursor-style 70%, 41%, 53%.
    static let ringFills: [CGFloat] = [0.70, 0.41, 0.53]
}

enum IconPalette {
    static let graphiteTop = CGColor(srgbRed: 0.267, green: 0.282, blue: 0.306, alpha: 1)
    static let graphiteBottom = CGColor(srgbRed: 0.098, green: 0.106, blue: 0.122, alpha: 1)
    static let sheen = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.07)
    static let sheenClear = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0)
    static let track = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.22)
    static let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
}

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func radians(_ degrees: CGFloat) -> CGFloat {
    degrees * .pi / 180
}

func squirclePath(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let halfWidth = rect.width / 2
    let halfHeight = rect.height / 2
    let steps = 720
    let power = 2 / IconGeometry.squircleExponent

    for step in 0...steps {
        let angle = 2 * CGFloat.pi * CGFloat(step) / CGFloat(steps)
        let cosine = cos(angle)
        let sine = sin(angle)
        let point = CGPoint(
            x: rect.midX + halfWidth * (cosine < 0 ? -1 : 1) * pow(abs(cosine), power),
            y: rect.midY + halfHeight * (sine < 0 ? -1 : 1) * pow(abs(sine), power)
        )

        if step == 0 {
            path.move(to: point)
        } else {
            path.addLine(to: point)
        }
    }

    path.closeSubpath()

    return path
}

func drawBackground(in context: CGContext, rect: CGRect) {
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [IconPalette.graphiteTop, IconPalette.graphiteBottom] as CFArray,
        locations: [0, 1]
    )!

    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.minY),
        options: []
    )

    let sheen = CGGradient(
        colorsSpace: colorSpace,
        colors: [IconPalette.sheen, IconPalette.sheenClear] as CFArray,
        locations: [0, 1]
    )!

    context.drawLinearGradient(
        sheen,
        start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.midY),
        options: []
    )
}

func drawRings(in context: CGContext, rect: CGRect, canvas: CGFloat) {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let lineWidth = IconGeometry.ringWidth * canvas

    for (index, fill) in IconGeometry.ringFills.enumerated() {
        let radius = (IconGeometry.outerRadius - CGFloat(index) * (IconGeometry.ringWidth + IconGeometry.ringGap)) * canvas
        let start = CGFloat.pi / 2

        context.saveGState()
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)

        context.setStrokeColor(IconPalette.track)
        context.addArc(center: center, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
        context.strokePath()

        // Clockwise from 12 o'clock; CoreGraphics y points up.
        context.setStrokeColor(IconPalette.white)
        context.addArc(center: center, radius: radius, startAngle: start, endAngle: start - 2 * .pi * fill, clockwise: true)
        context.strokePath()
        context.restoreGState()
    }
}

func makeIcon(pixels: Int) -> CGImage {
    let canvas = CGFloat(pixels)
    let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    let side = canvas * IconGeometry.squircleScale
    let squircle = CGRect(
        x: (canvas - side) / 2,
        y: (canvas - side) / 2,
        width: side,
        height: side
    )

    context.saveGState()
    context.addPath(squirclePath(in: squircle))
    context.clip()
    drawBackground(in: context, rect: squircle)
    context.restoreGState()

    drawRings(in: context, rect: squircle, canvas: canvas)

    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let representation = NSBitmapImageRep(cgImage: image)
    representation.size = NSSize(width: image.width, height: image.height)

    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw IconError.message("Could not encode \(url.lastPathComponent).")
    }

    try data.write(to: url)
}

enum IconError: Error {
    case message(String)
}

let root = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
let output = root.appendingPathComponent("Resources/AppIcon.icns")

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    try writePNG(makeIcon(pixels: points), to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try writePNG(
        makeIcon(pixels: points * 2),
        to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png")
    )
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["--convert", "icns", iconset.path, "--output", output.path]
try iconutil.run()
iconutil.waitUntilExit()

guard iconutil.terminationStatus == 0 else {
    throw IconError.message("iconutil failed with status \(iconutil.terminationStatus).")
}

try? FileManager.default.removeItem(at: iconset)

print("Wrote \(output.path)")
