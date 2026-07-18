import AppKit
import CoreGraphics

let canvas = 1024.0
let scale = canvas / 1024.0

func px(_ v: Double) -> CGFloat { CGFloat(v * scale) }

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvas),
    pixelsHigh: Int(canvas),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else { fatalError("no rep") }

let nsCtx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = nsCtx
let ctx = nsCtx.cgContext

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: a
    )
}

let bodyInset = 100.0
let bodySize = canvas - bodyInset * 2
let corner = bodySize * 0.2237
let bodyRect = CGRect(x: px(bodyInset), y: px(bodyInset), width: px(bodySize), height: px(bodySize))
let bodyPath = CGPath(roundedRect: bodyRect, cornerWidth: px(corner), cornerHeight: px(corner), transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: px(-14)), blur: px(34), color: color(0x000000, 0.28))
ctx.addPath(bodyPath)
ctx.setFillColor(color(0x0A84FF))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
let space = CGColorSpaceCreateDeviceRGB()
let gradient = CGGradient(
    colorsSpace: space,
    colors: [color(0x3B9BFF), color(0x0A6CFF), color(0x0056E0)] as CFArray,
    locations: [0, 0.55, 1]
)!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: bodyRect.midX, y: bodyRect.maxY),
    end: CGPoint(x: bodyRect.midX, y: bodyRect.minY),
    options: []
)

let sheen = CGGradient(
    colorsSpace: space,
    colors: [color(0xFFFFFF, 0.18), color(0xFFFFFF, 0.0)] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    sheen,
    start: CGPoint(x: bodyRect.midX, y: bodyRect.maxY),
    end: CGPoint(x: bodyRect.midX, y: bodyRect.midY),
    options: []
)
ctx.restoreGState()

let heights: [Double] = [0.30, 0.52, 0.78, 0.46, 1.0, 0.64, 0.88, 0.40, 0.58, 0.26]
let barWidth = 46.0
let gap = 40.0
let maxBarHeight = 470.0
let totalWidth = Double(heights.count) * barWidth + Double(heights.count - 1) * gap
let startX = (canvas - totalWidth) / 2
let centerY = canvas / 2 + 8

ctx.setFillColor(color(0xFFFFFF))
for (i, h) in heights.enumerated() {
    let bh = maxBarHeight * h
    let x = startX + Double(i) * (barWidth + gap)
    let rect = CGRect(x: px(x), y: px(centerY - bh / 2), width: px(barWidth), height: px(bh))
    let bar = CGPath(roundedRect: rect, cornerWidth: px(barWidth / 2), cornerHeight: px(barWidth / 2), transform: nil)
    ctx.addPath(bar)
    ctx.fillPath()
}

let dotRadius = 62.0
let dotCenter = CGPoint(x: px(canvas - bodyInset - 150), y: px(bodyInset + 150))
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: px(-6)), blur: px(16), color: color(0x000000, 0.30))
ctx.setFillColor(color(0xFF3B30))
ctx.addEllipse(in: CGRect(
    x: dotCenter.x - px(dotRadius),
    y: dotCenter.y - px(dotRadius),
    width: px(dotRadius * 2),
    height: px(dotRadius * 2)
))
ctx.fillPath()
ctx.restoreGState()

ctx.setFillColor(color(0xFFFFFF, 0.30))
ctx.addEllipse(in: CGRect(
    x: dotCenter.x - px(dotRadius),
    y: dotCenter.y - px(dotRadius),
    width: px(dotRadius * 2),
    height: px(dotRadius * 2)
))
ctx.addEllipse(in: CGRect(
    x: dotCenter.x - px(dotRadius - 12),
    y: dotCenter.y - px(dotRadius - 12),
    width: px((dotRadius - 12) * 2),
    height: px((dotRadius - 12) * 2)
))
ctx.fillPath(using: .evenOdd)

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("no png") }
try! data.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
