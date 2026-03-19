#!/usr/bin/swift
// make_icon.swift — Generates TTracker.icns from scratch using CoreGraphics.
// Run: swift make_icon.swift
import AppKit
import CoreGraphics

let iconsetDir = "./TTracker.iconset"
try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

// All required sizes for a full .icns
let sizes: [(Int, String)] = [
    (16,   "icon_16x16"),
    (32,   "icon_16x16@2x"),
    (32,   "icon_32x32"),
    (64,   "icon_32x32@2x"),
    (128,  "icon_128x128"),
    (256,  "icon_128x128@2x"),
    (256,  "icon_256x256"),
    (512,  "icon_256x256@2x"),
    (512,  "icon_512x512"),
    (1024, "icon_512x512@2x"),
]

// MARK: - Drawing

func drawIcon(size: Int) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()

    let s   = CGFloat(size)
    let cx  = s / 2
    let cy  = s / 2
    let ctx = NSGraphicsContext.current!.cgContext

    // ── Background: rounded rect with a deep blue gradient ────────────────
    let cr   = s * 0.22
    let rect = CGRect(x: 0, y: 0, width: s, height: s)
    let bg   = CGPath(roundedRect: rect, cornerWidth: cr, cornerHeight: cr, transform: nil)

    ctx.saveGState()
    ctx.addPath(bg)
    ctx.clip()

    let topColor = CGColor(red: 0.14, green: 0.35, blue: 0.65, alpha: 1.0)   // #245AAA
    let botColor = CGColor(red: 0.07, green: 0.16, blue: 0.33, alpha: 1.0)   // #122955
    let space    = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(colorsSpace: space,
                              colors: [topColor, botColor] as CFArray,
                              locations: [0.0, 1.0])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: cx, y: s),
                           end:   CGPoint(x: cx, y: 0),
                           options: [])
    ctx.restoreGState()

    // ── Clock circle ──────────────────────────────────────────────────────
    let margin = s * 0.14
    let r      = (s - 2 * margin) / 2
    let lw     = max(1.0, s * 0.055)

    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.88))
    ctx.setLineWidth(lw)
    ctx.strokeEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))

    // ── Tick marks at 12, 3, 6, 9 (only at ≥ 64 px) ─────────────────────
    if size >= 64 {
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.45))
        ctx.setLineWidth(max(1.0, s * 0.03))
        ctx.setLineCap(.butt)
        for i in 0..<4 {
            let a  = Double(i) * Double.pi / 2
            let r1 = Double(r) - Double(lw) / 2 - Double(s) * 0.03
            let r2 = r1 - Double(s) * 0.09
            ctx.move(to: CGPoint(x: cx + CGFloat(cos(a)) * CGFloat(r1),
                                 y: cy + CGFloat(sin(a)) * CGFloat(r1)))
            ctx.addLine(to: CGPoint(x: cx + CGFloat(cos(a)) * CGFloat(r2),
                                    y: cy + CGFloat(sin(a)) * CGFloat(r2)))
            ctx.strokePath()
        }
    }

    // ── Clock hands at 10:10 ──────────────────────────────────────────────
    // y-up coordinate system: angle measured CCW from east (positive x).
    // "clock angle" = angle from 12 going CW = π/2 - 2π*(h/12) in math coords.
    ctx.setLineCap(.round)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1.0))

    // Hour hand — 10 o'clock
    let hourAngle = Double.pi / 2 - Double.pi * 2 * (10.0 / 12.0)
    let hourLen   = Double(r) * 0.52
    ctx.setLineWidth(max(1.5, s * 0.075))
    ctx.move(to: CGPoint(x: cx, y: cy))
    ctx.addLine(to: CGPoint(x: cx + CGFloat(cos(hourAngle) * hourLen),
                             y: cy + CGFloat(sin(hourAngle) * hourLen)))
    ctx.strokePath()

    // Minute hand — 10 minutes (= 2 o'clock position)
    let minAngle = Double.pi / 2 - Double.pi * 2 * (10.0 / 60.0)
    let minLen   = Double(r) * 0.70
    ctx.setLineWidth(max(1.0, s * 0.050))
    ctx.move(to: CGPoint(x: cx, y: cy))
    ctx.addLine(to: CGPoint(x: cx + CGFloat(cos(minAngle) * minLen),
                             y: cy + CGFloat(sin(minAngle) * minLen)))
    ctx.strokePath()

    // ── Centre dot (coral / recording indicator) ──────────────────────────
    let dotR = s * 0.065
    ctx.setFillColor(CGColor(red: 1.0, green: 0.42, blue: 0.28, alpha: 1.0))
    ctx.fillEllipse(in: CGRect(x: cx - dotR, y: cy - dotR, width: 2 * dotR, height: 2 * dotR))

    img.unlockFocus()
    return img
}

// MARK: - Export PNGs → .iconset → .icns

for (size, name) in sizes {
    let img  = drawIcon(size: size)
    let tiff = img.tiffRepresentation!
    let rep  = NSBitmapImageRep(data: tiff)!
    let png  = rep.representation(using: .png, properties: [:])!
    let url  = URL(fileURLWithPath: "\(iconsetDir)/\(name).png")
    try! png.write(to: url)
    print("  \(name).png  (\(size)×\(size))")
}

print("\nRunning iconutil…")
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments     = ["-c", "icns", "-o", "AppIcon.icns", iconsetDir]
try! proc.run()
proc.waitUntilExit()

if proc.terminationStatus == 0 {
    print("✓  AppIcon.icns written")
    try? FileManager.default.removeItem(atPath: iconsetDir)
    print("   (cleaned up \(iconsetDir))")
} else {
    print("✗  iconutil failed (status \(proc.terminationStatus))")
}
