#!/usr/bin/swift
import AppKit

let size = CGFloat(1024)

let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

    // Blue → indigo gradient background
    let colors = [
        CGColor(red: 0.15, green: 0.38, blue: 0.88, alpha: 1),
        CGColor(red: 0.32, green: 0.12, blue: 0.72, alpha: 1)
    ] as CFArray
    let space = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
        start: CGPoint(x: 0, y: 0), end: CGPoint(x: size, y: size), options: [])

    // Clock shifted into upper portion
    let cx = size / 2
    let cy = CGFloat(620)
    let radius = CGFloat(245)

    // Clock face
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
    ctx.setLineWidth(44)
    ctx.addArc(center: CGPoint(x: cx, y: cy), radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()

    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
    ctx.addArc(center: CGPoint(x: cx, y: cy), radius: radius - 22, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.fillPath()

    ctx.setLineCap(.round)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))

    // Clock hands at 10:10
    let hourAngle   = CGFloat.pi * 5 / 6
    let minuteAngle = CGFloat.pi / 6

    ctx.setLineWidth(50)
    ctx.move(to: CGPoint(x: cx, y: cy))
    ctx.addLine(to: CGPoint(x: cx + 140 * cos(hourAngle), y: cy + 140 * sin(hourAngle)))
    ctx.strokePath()

    ctx.setLineWidth(34)
    ctx.move(to: CGPoint(x: cx, y: cy))
    ctx.addLine(to: CGPoint(x: cx + 200 * cos(minuteAngle), y: cy + 200 * sin(minuteAngle)))
    ctx.strokePath()

    // Center dot
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.addArc(center: CGPoint(x: cx, y: cy), radius: 28, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.fillPath()

    // 汉字 — below the clock
    let font = NSFont(name: "PingFang SC Semibold", size: 190) ??
               NSFont(name: "PingFang SC", size: 190) ??
               NSFont.systemFont(ofSize: 190, weight: .semibold)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white
    ]
    let str = NSAttributedString(string: "汉字", attributes: attrs)
    let textSize = str.size()
    // Place text centered, in the lower band (y=185 centers it between bottom and clock base)
    str.draw(at: NSPoint(x: cx - textSize.width / 2, y: 185 - textSize.height / 2))

    return true
}

let tiff = image.tiffRepresentation!
let rep = NSBitmapImageRep(data: tiff)!
let png = rep.representation(using: .png, properties: [:])!
let path = "/Users/tamara/Desktop/MBTracker/MBTracker/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
try! png.write(to: URL(fileURLWithPath: path))
print("Done: \(path)")
