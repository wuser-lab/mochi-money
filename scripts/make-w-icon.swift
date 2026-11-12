import AppKit
let output = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024), flipped: false) { rect in
    NSGradient(colors: [NSColor(red: 0.06, green: 0.12, blue: 0.14, alpha: 1), NSColor(red: 0.13, green: 0.29, blue: 0.26, alpha: 1)])!.draw(in: rect, angle: 45)
    let mark = NSBezierPath()
    mark.move(to: NSPoint(x: 228, y: 664)); mark.line(to: NSPoint(x: 356, y: 342))
    mark.line(to: NSPoint(x: 512, y: 590)); mark.line(to: NSPoint(x: 668, y: 342)); mark.line(to: NSPoint(x: 796, y: 664))
    mark.lineWidth = 78; mark.lineCapStyle = .round; mark.lineJoinStyle = .round
    NSColor(red: 0.80, green: 0.98, blue: 0.89, alpha: 1).setStroke(); mark.stroke()
    return true
}
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
