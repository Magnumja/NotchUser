// Builds the app icon (1024x1024 PNG) from the logo: the notch mark, without the wordmark,
// on a dark glass squircle.
// Usage: swift Tools/make_icon.swift Assets/logo.png Assets/AppIcon.png
import AppKit

let args = CommandLine.arguments
let logoPath = args.count > 1 ? args[1] : "Assets/logo.png"
let out = args.count > 2 ? args[2] : "Assets/AppIcon.png"

guard let logo = NSImage(contentsOfFile: logoPath),
      let logoCG = logo.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("can't read \(logoPath)")
}
// The mark sits in this band of the 1254x1254 logo (top-left origin); the wordmark is below it.
let s = CGFloat(logoCG.width) / 1254
let markCrop = CGRect(x: 205 * s, y: 430 * s, width: 845 * s, height: 270 * s)
let mark = logoCG.cropping(to: markCrop)!

let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func white(_ a: CGFloat) -> NSColor { NSColor(white: 1, alpha: a) }

// macOS icon grid: 824pt body inset 100pt.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: NSColor(white: 0, alpha: 0.4).cgColor)
NSColor.black.setFill()
squircle.fill()
ctx.restoreGState()

ctx.saveGState()
squircle.addClip()
NSGradient(colors: [NSColor(white: 0.13, alpha: 1), NSColor(white: 0.02, alpha: 1)])!.draw(in: body, angle: -90)
// Soft light behind the mark and a frosted sheen on top.
let c = CGPoint(x: 512, y: 520)
NSGradient(colors: [white(0.10), white(0)])!.draw(fromCenter: c, radius: 0, toCenter: c, radius: 420, options: [])
NSGradient(colors: [white(0.12), white(0)])!.draw(in: CGRect(x: 100, y: 600, width: 824, height: 324), angle: -90)

// The mark, scaled to the body width with some margin. Its black background
// blends into the dark squircle; .screen keeps only the light metal.
let markW: CGFloat = 700
let markH = markW * CGFloat(mark.height) / CGFloat(mark.width)
ctx.setBlendMode(.screen)
ctx.draw(mark, in: CGRect(x: 512 - markW / 2, y: 512 - markH / 2, width: markW, height: markH))
ctx.setBlendMode(.normal)
ctx.restoreGState()

// Glass rim.
white(0.18).setStroke()
squircle.lineWidth = 4
squircle.stroke()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("icon: \(out)")
