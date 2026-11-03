import AppKit

// Draws Genboard's 1024×1024 app icon: a pedigree of cards on a navy board, one parent in a
// dashed orange "open theory" border. Usage: swift tools/make_icon.swift <output.png>
// Then regenerate the asset catalog sizes with tools/make_icon.sh.
let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
// Work in top-left coordinates.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// macOS icon grid: 824×824 body with ~185 corner radius, centered, with a soft shadow.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: color(0x000000, 0.45))
ctx.addPath(bodyPath)
ctx.setFillColor(color(0x1A2340))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [color(0x33457A), color(0x151C36)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
// Faint dot grid, like the board.
ctx.setFillColor(color(0xFFFFFF, 0.07))
for x in stride(from: 140.0, through: 900, by: 48) {
    for y in stride(from: 140.0, through: 900, by: 48) {
        ctx.fillEllipse(in: CGRect(x: x - 3, y: y - 3, width: 6, height: 6))
    }
}

// Elbow lines from the child to both parents.
let child = CGRect(x: 170, y: 437, width: 280, height: 150)
let father = CGRect(x: 574, y: 236, width: 280, height: 150)
let mother = CGRect(x: 574, y: 638, width: 280, height: 150)
let midX: CGFloat = 512
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.setLineWidth(16)
let lines = CGMutablePath()
lines.move(to: CGPoint(x: child.maxX, y: child.midY))
lines.addLine(to: CGPoint(x: midX, y: child.midY))
lines.move(to: CGPoint(x: midX, y: father.midY))
lines.addLine(to: CGPoint(x: midX, y: mother.midY))
ctx.addPath(lines)
ctx.setStrokeColor(color(0xC9D3EA, 0.85))
ctx.strokePath()
ctx.setLineWidth(16)
for (target, tint) in [(father, color(0xF2A33A)), (mother, color(0x46C2C9))] {
    ctx.move(to: CGPoint(x: midX, y: target.midY))
    ctx.addLine(to: CGPoint(x: target.minX, y: target.midY))
    ctx.setStrokeColor(tint)
    ctx.strokePath()
}

func card(_ rect: CGRect, fill: CGColor, border: CGColor, dashed: Bool, avatar: CGColor) {
    let path = CGPath(roundedRect: rect, cornerWidth: 30, cornerHeight: 30, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 8), blur: 16, color: color(0x000000, 0.35))
    ctx.addPath(path)
    ctx.setFillColor(color(0x202B4D))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(path)
    ctx.setFillColor(fill)
    ctx.fillPath()
    ctx.addPath(path)
    ctx.setStrokeColor(border)
    ctx.setLineWidth(10)
    ctx.setLineDash(phase: 0, lengths: dashed ? [26, 16] : [])
    ctx.strokePath()
    ctx.setLineDash(phase: 0, lengths: [])
    // Avatar and two text bars.
    let avatarRect = CGRect(x: rect.minX + 30, y: rect.midY - 34, width: 68, height: 68)
    ctx.setFillColor(avatar)
    ctx.fillEllipse(in: avatarRect)
    ctx.setFillColor(color(0xFFFFFF, 0.9))
    ctx.addPath(CGPath(roundedRect: CGRect(x: avatarRect.maxX + 24, y: rect.midY - 30, width: 132, height: 22),
                       cornerWidth: 11, cornerHeight: 11, transform: nil))
    ctx.fillPath()
    ctx.setFillColor(color(0xFFFFFF, 0.45))
    ctx.addPath(CGPath(roundedRect: CGRect(x: avatarRect.maxX + 24, y: rect.midY + 10, width: 92, height: 18),
                       cornerWidth: 9, cornerHeight: 9, transform: nil))
    ctx.fillPath()
}

card(child, fill: color(0x3D7BD9, 0.55), border: color(0x7FB0FF), dashed: false, avatar: color(0x9CC2FF))
card(father, fill: color(0xF2A33A, 0.22), border: color(0xF2A33A), dashed: true, avatar: color(0xF7C27A))
card(mother, fill: color(0x46C2C9, 0.22), border: color(0x46C2C9), dashed: false, avatar: color(0x8EDDE1))

// Subtle top highlight on the body.
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(bodyPath)
ctx.setStrokeColor(color(0xFFFFFF, 0.10))
ctx.setLineWidth(3)
ctx.strokePath()
ctx.restoreGState()

NSGraphicsContext.current = nil
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
