#!/usr/bin/env swift
// Build Contents/Resources/AppIcon.icns from a single master PNG.
//
//   swift scripts/make-icon.swift <source.png> <out.icns>
//
// Why a Swift script and not sips/iconutil alone: macOS app icons are *not*
// full-bleed. The artwork body belongs on the 824x824 grid inside a 1024x1024
// canvas, with the surrounding margin fully transparent, or the icon reads as
// oversized next to every other tile in the Dock. `sips -p` can pad, but only
// with an opaque --padColor, so it cannot produce that margin. CoreGraphics
// can, it renders every size straight from the master instead of chaining
// downscales, and Swift is already a build requirement here.
//
// The artwork is also clipped to a rounded rect, so a master with an opaque
// background still gets clean transparent corners instead of showing up as a
// square.
import CoreGraphics
import Foundation
import ImageIO

// Apple's macOS icon grid: an 824x824 body on a 1024x1024 canvas, corner
// radius 185.4. Tune these two if the icon reads too large/small or if the
// mask disagrees visibly with the corners baked into the artwork.
let bodyRatio: CGFloat = 824.0 / 1024.0
let cornerRatio: CGFloat = 185.4 / 824.0

// Every representation `iconutil` expects; it rejects an incomplete set.
// (file name, pixel size)
let variants: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func note(_ message: String) {
    print("make-icon: \(message)")
}

func warn(_ message: String) {
    FileHandle.standardError.write("make-icon: warning: \(message)\n".data(using: .utf8)!)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("make-icon: \(message)\n".data(using: .utf8)!)
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 3 else {
    fail("usage: swift scripts/make-icon.swift <source.png> <out.icns>")
}
let sourceURL = URL(fileURLWithPath: args[1])
let outputURL = URL(fileURLWithPath: args[2])

guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let master = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    fail("could not read an image from \(sourceURL.path)")
}
guard master.width > 0, master.height > 0 else {
    fail("\(sourceURL.path) has zero extent")
}
if master.width < 1024 || master.height < 1024 {
    warn(
        "master is \(master.width)x\(master.height); 1024x1024 or larger is "
            + "recommended so the @2x sizes stay sharp."
    )
}

// Image generators typically return an opaque background filling the canvas
// around the icon body. Clipping at the image bounds would then leave that
// background as a frame around the rounded rect, so find the artwork's real
// extent first. Returns nil when the border is not a uniform colour, or when
// the result looks implausible — in both cases there is nothing safe to trim.
func contentBounds(of image: CGImage) -> CGRect? {
    let w = image.width, h = image.height
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(
              data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          )
    else { return nil }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let raw = ctx.data else { return nil }

    let rowBytes = ctx.bytesPerRow
    let px = raw.bindMemory(to: UInt8.self, capacity: rowBytes * h)
    func pixel(_ x: Int, _ y: Int) -> (Int, Int, Int, Int) {
        let o = y * rowBytes + x * 4
        return (Int(px[o]), Int(px[o + 1]), Int(px[o + 2]), Int(px[o + 3]))
    }

    // Anti-aliasing and subtle gradients mean the border is never bit-exact.
    let tolerance = 12
    let bg = pixel(0, 0)
    func isBackground(_ p: (Int, Int, Int, Int)) -> Bool {
        if p.3 < 8, bg.3 < 8 { return true }  // both effectively transparent
        return abs(p.0 - bg.0) <= tolerance && abs(p.1 - bg.1) <= tolerance
            && abs(p.2 - bg.2) <= tolerance && abs(p.3 - bg.3) <= tolerance
    }
    // All four corners must agree, or this is artwork that bleeds to the edge.
    for corner in [pixel(w - 1, 0), pixel(0, h - 1), pixel(w - 1, h - 1)]
    where !isBackground(corner) {
        return nil
    }

    func rowIsBackground(_ y: Int) -> Bool {
        for x in 0..<w where !isBackground(pixel(x, y)) { return false }
        return true
    }
    func colIsBackground(_ x: Int) -> Bool {
        for y in 0..<h where !isBackground(pixel(x, y)) { return false }
        return true
    }
    var top = 0, bottom = h - 1, left = 0, right = w - 1
    while top < bottom, rowIsBackground(top) { top += 1 }
    while bottom > top, rowIsBackground(bottom) { bottom -= 1 }
    while left < right, colIsBackground(left) { left += 1 }
    while right > left, colIsBackground(right) { right -= 1 }

    let rect = CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
    // Nothing to do, or so much matched that the detection is not trustworthy.
    guard rect.width < CGFloat(w) || rect.height < CGFloat(h) else { return nil }
    guard rect.width >= CGFloat(w) / 2, rect.height >= CGFloat(h) / 2 else {
        warn("ignoring an implausible border trim of \(w)x\(h) down to "
            + "\(Int(rect.width))x\(Int(rect.height))")
        return nil
    }
    // The scan stops at the outermost pixel that differs from the background,
    // and that pixel is the anti-aliased blend between the two. Kept, it
    // composites as a dark rim around the finished icon, so shed it. Such a
    // seam is ~1px wide whatever the master's resolution, so the inset is a
    // fixed count rather than a proportion.
    let seam: CGFloat = 2
    let deseamed = rect.insetBy(dx: seam, dy: seam)
    return deseamed.width > 0 && deseamed.height > 0 ? deseamed : rect
}

// What actually gets drawn: the master with any uniform border removed.
let artwork: CGImage = {
    guard let bounds = contentBounds(of: master), let cropped = master.cropping(to: bounds)
    else { return master }
    note("trimmed a uniform border: \(master.width)x\(master.height) -> "
        + "\(cropped.width)x\(cropped.height)")
    return cropped
}()

// Render one square representation: artwork aspect-fitted onto the body grid,
// centred on a transparent canvas, clipped to a rounded rect.
func render(side: Int) -> CGImage {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(
              data: nil,
              width: side,
              height: side,
              bitsPerComponent: 8,
              bytesPerRow: 0,
              space: space,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          )
    else {
        fail("could not create a \(side)x\(side) bitmap context")
    }

    let canvas = CGFloat(side)
    let body = canvas * bodyRatio
    // Aspect-fit, so a non-square master is letterboxed rather than stretched.
    let scale = min(body / CGFloat(artwork.width), body / CGFloat(artwork.height))
    let drawn = CGSize(width: CGFloat(artwork.width) * scale, height: CGFloat(artwork.height) * scale)
    let rect = CGRect(
        x: (canvas - drawn.width) / 2,
        y: (canvas - drawn.height) / 2,
        width: drawn.width,
        height: drawn.height
    )

    ctx.interpolationQuality = .high
    let radius = min(drawn.width, drawn.height) * cornerRatio
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
    ctx.draw(artwork, in: rect)

    guard let image = ctx.makeImage() else { fail("could not rasterise the \(side)x\(side) variant") }
    return image
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
    else {
        fail("could not create \(url.path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fail("could not write \(url.path)") }
}

// Stage the .iconset next to the output. It is inside build/ (gitignored), so
// leaving it behind is free and makes the individual sizes inspectable.
let iconsetURL = outputURL.deletingLastPathComponent()
    .appendingPathComponent(outputURL.deletingPathExtension().lastPathComponent + ".iconset")
let fm = FileManager.default
try? fm.removeItem(at: iconsetURL)
do {
    try fm.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
} catch {
    fail("could not create \(iconsetURL.path): \(error.localizedDescription)")
}

// Render each distinct pixel size once; 32/256/512 are each used twice.
var cache: [Int: CGImage] = [:]
for (name, side) in variants {
    let image: CGImage
    if let cached = cache[side] {
        image = cached
    } else {
        image = render(side: side)
        cache[side] = image
    }
    writePNG(image, to: iconsetURL.appendingPathComponent(name))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
do {
    try iconutil.run()
} catch {
    fail("could not run /usr/bin/iconutil: \(error.localizedDescription)")
}
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fail("iconutil failed with status \(iconutil.terminationStatus)")
}

print("Wrote \(outputURL.path) (\(cache.count) distinct sizes, \(variants.count) representations)")
