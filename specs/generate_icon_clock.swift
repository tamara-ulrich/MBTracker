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
    let locations: [CGFloat] = [0, 1]
    let space = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(colorsSpace: space, colors: colors, locations: locations)!
    ctx.drawLinearGradient(gradient,
        start: CGPoint(x: 0, y: 0),
        end: CGPoint(x: size, y: size),
        options: [])

    let cx = size / 2, cy = size / 2

    // Clock face circle
    let radius = CGFloat(290)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
    ctx.setLineWidth(44)
    ctx.addArc(center: CGPoint(x: cx, y: cy), radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()

    // Subtle fill inside clock
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
    ctx.addArc(center: CGPoint(x: cx, y: cy), radius: radius - 22, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.fillPath()

    ctx.setLineCap(.round)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))

    // Clock at 10:10
    // In CoreGraphics with y-up: 0° = right (3 o'clock), 90° = up (12 o'clock)
    // 10 o'clock = 150° = 5π/6 from x-axis
    // 2 o'clock  =  30° = π/6 from x-axis
    let hourAngle  = CGFloat.pi * 5 / 6   // 10 o'clock
    let minuteAngle = CGFloat.pi / 6       // 2 o'clock

    // Hour hand (shorter)
    ctx.setLineWidth(52)
    ctx.move(to: CGPoint(x: cx, y: cy))
    ctx.addLine(to: CGPoint(x: cx + 160 * cos(hourAngle), y: cy + 160 * sin(hourAngle)))
    ctx.strokePath()

    // Minute hand (longer)
    ctx.setLineWidth(36)
    ctx.move(to: CGPoint(x: cx, y: cy))
    ctx.addLine(to: CGPoint(x: cx + 235 * cos(minuteAngle), y: cy + 235 * sin(minuteAngle)))
    ctx.strokePath()

    // Center dot
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.addArc(center: CGPoint(x: cx, y: cy), radius: 30, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.fillPath()

    return true
}

let tiff = image.tiffRepresentation!
let rep = NSBitmapImageRep(data: tiff)!
let png = rep.representation(using: .png, properties: [:])!
let path = "/Users/tamara/Desktop/MBTracker/MBTracker/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
try! png.write(to: URL(fileURLWithPath: path))
print("Done: \(path)")
