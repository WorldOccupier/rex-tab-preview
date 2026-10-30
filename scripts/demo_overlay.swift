// Draws the stills and key caps that record_demo.sh layers over the recording
// with ffmpeg: bg.png (backdrop and window shadow), mask.png (the window's
// rounded corners) and caps/NNNN.png (transparent, one per frame). Prints the
// time of every key press, one per line, for the clicks.
// Usage: swift demo_overlay.swift KEYS_TXT OUT_DIR WINDOW_W WINDOW_H
import AppKit

let (W, H, FPS, SECONDS) = (1920, 1080, 30, 14.0)
let args = CommandLine.arguments
let keysText = try! String(contentsOfFile: args[1], encoding: .utf8)
let out = URL(fileURLWithPath: args[2])
let winW = CGFloat(Double(args[3])!)
let winH = CGFloat(Double(args[4])!)
let winY = (CGFloat(H) - winH) / 2
let winX = (CGFloat(W) - winW) / 2

let capH: CGFloat = 72, capGap: CGFloat = 12, pad: CGFloat = 16
// The last key of a shortcut goes down this long before its action runs, and
// the keys before it this much earlier again.
let lastKeyLead = 0.12, keyStep = 0.16
// How long the caps stay after the action, then how long they take to leave.
let hold = 1.1, leave = 0.25, press = 0.12

struct Shortcut { var keys: [(String, Double)]; var at: Double }
let shortcuts: [Shortcut] = keysText.split(separator: "\n").compactMap { line in
    let parts = line.split(separator: " ", maxSplits: 1)
    guard parts.count == 2, let at = Double(parts[0]) else { return nil }
    let keys = parts[1].split(separator: "+").map(String.init)
    let n = keys.count
    return Shortcut(keys: keys.enumerated().map { i, k in (k, at - lastKeyLead - keyStep * Double(n - 1 - i)) }, at: at)
}

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

/// Draws into a W x H canvas with the origin top left, like the video, and saves it as a PNG.
func png(_ path: URL, _ w: Int = W, _ h: Int = H, draw: (CGContext) -> Void) {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    draw(ctx)
    let dest = CGImageDestinationCreateWithURL(path as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}

func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

png(out.appendingPathComponent("bg.png")) { ctx in
    let gradient = CGGradient(colorsSpace: nil, colors: [color(0x4a4d55), color(0x26282d)] as CFArray, locations: [0, 1])!
    let center = CGPoint(x: CGFloat(W) / 2, y: CGFloat(H) * 0.35)
    ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: CGFloat(W) * 0.85, options: .drawsAfterEndLocation)
    ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: 56, color: color(0x000000, 0.75))
    ctx.addPath(rounded(CGRect(x: winX, y: winY, width: winW, height: winH), 14))
    ctx.setFillColor(color(0x000000))
    ctx.fillPath()
}

png(out.appendingPathComponent("mask.png"), Int(winW), Int(winH)) { ctx in
    ctx.setFillColor(color(0x000000))
    ctx.fill(CGRect(x: 0, y: 0, width: winW, height: winH))
    ctx.addPath(rounded(CGRect(x: 0, y: 0, width: winW, height: winH), 14))
    ctx.setFillColor(color(0xffffff))
    ctx.fillPath()
}

/// Ease-out with a slight overshoot past 1.
func backOut(_ p: Double) -> Double {
    let c = 1.7, q = p - 1
    return 1 + (c + 1) * q * q * q + c * q * q
}

func drawCaps(_ ctx: CGContext, _ t: Double) {
    guard let s = shortcuts.first(where: { t >= $0.keys[0].1 && t < $0.at + hold + leave }) else { return }
    let gone = min(max((t - s.at - hold) / leave, 0), 1)
    let widths = s.keys.map { max(capH, CGFloat($0.0.count) * 26 + 34) }
    let total = widths.reduce(0, +) + capGap * CGFloat(widths.count - 1)
    // Above the mode hints Rex shows at the bottom of the window.
    let (cx, y) = (CGFloat(W) / 2, CGFloat(H) - 290)
    // One layer, so the panel and caps fade out together instead of showing
    // through each other.
    ctx.saveGState()
    ctx.setAlpha(CGFloat(1 - gone))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.translateBy(x: 0, y: 14 * CGFloat(gone))
    ctx.addPath(rounded(CGRect(x: cx - total / 2 - pad, y: y - pad, width: total + pad * 2, height: capH + 6 + pad * 2), 22))
    ctx.setFillColor(color(0x0b0d12, 0.72))
    ctx.fillPath()
    var x = cx - total / 2
    for ((key, down), w) in zip(s.keys, widths) {
        defer { x += w + capGap }
        let since = t - down
        guard since >= 0 else { continue }
        // Pops in with a little overshoot, then the cap sinks while pressed.
        let pop = backOut(min(since / 0.22, 1))
        let pressed = since < press ? 1 : 1 - min((since - press) / 0.1, 1)
        let sink = 5 * CGFloat(pressed)
        let scale = CGFloat(0.6 + 0.4 * pop)
        ctx.saveGState()
        ctx.setAlpha(CGFloat(min(pop, 1)))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.translateBy(x: x + w / 2, y: y + capH / 2)
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -(x + w / 2), y: -(y + capH / 2))
        ctx.addPath(rounded(CGRect(x: x, y: y + 6, width: w, height: capH), 12))
        ctx.setFillColor(color(0x8a8f9c))
        ctx.fillPath()
        ctx.addPath(rounded(CGRect(x: x, y: y + sink, width: w, height: capH), 12))
        ctx.setFillColor(color(pressed > 0.5 ? 0xd9dce3 : 0xf4f5f8))
        ctx.fillPath()
        let size: CGFloat = key.count > 1 ? 26 : 36
        let label = NSAttributedString(string: key, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: NSColor(cgColor: color(0x1b1e26))!,
        ])
        let b = label.size()
        label.draw(at: CGPoint(x: x + (w - b.width) / 2, y: y + sink + (capH - b.height) / 2))
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

let caps = out.appendingPathComponent("caps")
try? FileManager.default.createDirectory(at: caps, withIntermediateDirectories: true)
for f in 0..<Int(SECONDS * Double(FPS)) {
    png(caps.appendingPathComponent(String(format: "%04d.png", f))) { drawCaps($0, Double(f) / Double(FPS)) }
}
for s in shortcuts { for (_, down) in s.keys { print(String(format: "%.3f", down)) } }
