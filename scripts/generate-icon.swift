#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

let size = 1024
let s = CGFloat(size)
let rect = CGRect(x: 0, y: 0, width: size, height: size)

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard
    let context = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
else { fatalError("Failed to create context") }

let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
NSGraphicsContext.current = nsContext

// --- App icon rounded rect background ---
let outerRadius = s * 0.22
let outerPath = NSBezierPath(roundedRect: rect, xRadius: outerRadius, yRadius: outerRadius)
outerPath.addClip()

// Background gradient (dark)
let bgColors: [CGFloat] = [
    0.10, 0.10, 0.14, 1.0,
    0.08, 0.08, 0.11, 1.0,
]
let bgGrad = CGGradient(
    colorSpace: colorSpace, colorComponents: bgColors,
    locations: [0.0, 1.0], count: 2)!
context.drawLinearGradient(
    bgGrad,
    start: CGPoint(x: s / 2, y: s), end: CGPoint(x: s / 2, y: 0), options: [])

// --- Terminal window frame ---
let margin = s * 0.10
let termRect = CGRect(x: margin, y: margin * 0.7, width: s - margin * 2, height: s - margin * 1.7)
let termRadius = s * 0.06
let termPath = NSBezierPath(roundedRect: termRect, xRadius: termRadius, yRadius: termRadius)

// Terminal background (slightly lighter)
NSColor(red: 0.13, green: 0.13, blue: 0.18, alpha: 1.0).setFill()
termPath.fill()

// Terminal border
NSColor(red: 0.28, green: 0.28, blue: 0.36, alpha: 1.0).setStroke()
termPath.lineWidth = s * 0.008
termPath.stroke()

// --- Title bar ---
let titleBarHeight = s * 0.08
let titleBarY = termRect.maxY - titleBarHeight
let titleBarRect = CGRect(
    x: termRect.minX, y: titleBarY,
    width: termRect.width, height: titleBarHeight)

// Title bar background
let titleBarPath = NSBezierPath()
titleBarPath.move(to: NSPoint(x: termRect.minX + termRadius, y: termRect.maxY))
titleBarPath.line(to: NSPoint(x: termRect.maxX - termRadius, y: termRect.maxY))
titleBarPath.appendArc(
    withCenter: NSPoint(x: termRect.maxX - termRadius, y: termRect.maxY - termRadius),
    radius: termRadius, startAngle: 90, endAngle: 0, clockwise: true)
titleBarPath.line(to: NSPoint(x: termRect.maxX, y: titleBarY))
titleBarPath.line(to: NSPoint(x: termRect.minX, y: titleBarY))
titleBarPath.line(to: NSPoint(x: termRect.minX, y: termRect.maxY - termRadius))
titleBarPath.appendArc(
    withCenter: NSPoint(x: termRect.minX + termRadius, y: termRect.maxY - termRadius),
    radius: termRadius, startAngle: 180, endAngle: 90, clockwise: true)
titleBarPath.close()

NSColor(red: 0.16, green: 0.16, blue: 0.22, alpha: 1.0).setFill()
titleBarPath.fill()

// Title bar separator line
context.setStrokeColor(red: 0.28, green: 0.28, blue: 0.36, alpha: 1.0)
context.setLineWidth(s * 0.005)
context.move(to: CGPoint(x: termRect.minX, y: titleBarY))
context.addLine(to: CGPoint(x: termRect.maxX, y: titleBarY))
context.strokePath()

// Traffic light dots
let dotRadius = s * 0.014
let dotY = titleBarY + titleBarHeight / 2
let dotStartX = termRect.minX + s * 0.045
let dotSpacing = s * 0.035

// Red dot
context.setFillColor(red: 1.0, green: 0.38, blue: 0.35, alpha: 1.0)
context.fillEllipse(in: CGRect(
    x: dotStartX - dotRadius, y: dotY - dotRadius,
    width: dotRadius * 2, height: dotRadius * 2))

// Yellow dot
context.setFillColor(red: 1.0, green: 0.78, blue: 0.25, alpha: 1.0)
context.fillEllipse(in: CGRect(
    x: dotStartX + dotSpacing - dotRadius, y: dotY - dotRadius,
    width: dotRadius * 2, height: dotRadius * 2))

// Green dot
context.setFillColor(red: 0.35, green: 0.85, blue: 0.45, alpha: 1.0)
context.fillEllipse(in: CGRect(
    x: dotStartX + dotSpacing * 2 - dotRadius, y: dotY - dotRadius,
    width: dotRadius * 2, height: dotRadius * 2))

// --- "a/n" text (centered in terminal body) ---
let bodyRect = CGRect(
    x: termRect.minX, y: termRect.minY,
    width: termRect.width, height: titleBarY - termRect.minY)

// "a" in green
let letterFont = NSFont.monospacedSystemFont(ofSize: s * 0.34, weight: .bold)
let slashFont = NSFont.monospacedSystemFont(ofSize: s * 0.28, weight: .regular)

let aAttrs: [NSAttributedString.Key: Any] = [
    .font: letterFont,
    .foregroundColor: NSColor(red: 0.35, green: 0.92, blue: 0.55, alpha: 1.0),
]
let slashAttrs: [NSAttributedString.Key: Any] = [
    .font: slashFont,
    .foregroundColor: NSColor(red: 0.45, green: 0.45, blue: 0.55, alpha: 0.7),
]
let nAttrs: [NSAttributedString.Key: Any] = [
    .font: letterFont,
    .foregroundColor: NSColor(red: 0.45, green: 0.65, blue: 1.0, alpha: 1.0),
]

let aStr = NSAttributedString(string: "a", attributes: aAttrs)
let slashStr = NSAttributedString(string: "/", attributes: slashAttrs)
let nStr = NSAttributedString(string: "n", attributes: nAttrs)

let aSize = aStr.size()
let slashSize = slashStr.size()
let nSize = nStr.size()

let totalWidth = aSize.width + slashSize.width + nSize.width
let textHeight = max(aSize.height, max(slashSize.height, nSize.height))

let textX = bodyRect.midX - totalWidth / 2
let textY = bodyRect.midY - textHeight / 2 - s * 0.01

aStr.draw(at: NSPoint(x: textX, y: textY))
slashStr.draw(at: NSPoint(
    x: textX + aSize.width,
    y: textY + (aSize.height - slashSize.height) / 2))
nStr.draw(at: NSPoint(x: textX + aSize.width + slashSize.width, y: textY))

// --- Subtle cursor blink after text ---
let cursorX = textX + totalWidth + s * 0.025
let cursorY = textY + s * 0.02
let cursorW = s * 0.035
let cursorH = textHeight * 0.65
context.setFillColor(red: 0.35, green: 0.92, blue: 0.55, alpha: 0.5)
context.fill(CGRect(x: cursorX, y: cursorY, width: cursorW, height: cursorH))

// --- Export ---
guard let cgImage = context.makeImage() else { fatalError("Failed to create image") }

let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
bitmapRep.size = NSSize(width: size, height: size)
guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
    fatalError("Failed to create PNG")
}

let outputPath = (CommandLine.arguments.count > 1) ? CommandLine.arguments[1] : "icon_1024.png"
try! pngData.write(to: URL(fileURLWithPath: outputPath))
print("Icon saved to \(outputPath)")
