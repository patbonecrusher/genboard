import AppKit

// Draws the 1200×630 social card used when a link to the website is shared.
// Usage: swift tools/make_social_card.swift <icon-1024.png> <output.png>
let width: CGFloat = 1200, height: CGFloat = 630
let icon = NSImage(contentsOfFile: CommandLine.arguments[1])!
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let background = NSGradient(starting: NSColor(srgbRed: 0.20, green: 0.27, blue: 0.48, alpha: 1),
                            ending: NSColor(srgbRed: 0.08, green: 0.11, blue: 0.21, alpha: 1))!
background.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -90)

icon.draw(in: NSRect(x: 70, y: 135, width: 360, height: 360))

let title = NSAttributedString(string: "Genboard", attributes: [
    .font: NSFont.systemFont(ofSize: 92, weight: .bold),
    .foregroundColor: NSColor.white,
])
title.draw(at: NSPoint(x: 470, y: 330))

let paragraph = NSMutableParagraphStyle()
paragraph.lineSpacing = 6
let tagline = NSAttributedString(string: "A research workbench for genealogy on the Mac: sessions, a board for theories, and a family tree.",
                                 attributes: [
    .font: NSFont.systemFont(ofSize: 34, weight: .regular),
    .foregroundColor: NSColor(white: 1, alpha: 0.78),
    .paragraphStyle: paragraph,
])
tagline.draw(in: NSRect(x: 474, y: 140, width: 660, height: 180))

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
