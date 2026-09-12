import AppKit

// 生成 FundBar 应用图标:深蓝渐变圆角矩形 + 上升趋势折线(红涨绿跌配色点)
// 用法:make-icon <输出路径.png>

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let bounds = NSRect(origin: .zero, size: size)
// 图标安全区:内容画在 inset 100 的圆角矩形里(macOS 会自动加圆角遮罩外的透明边)
let inset = NSRect(x: 100, y: 100, width: 824, height: 824)
let radius: CGFloat = 184
let clip = NSBezierPath(roundedRect: inset, xRadius: radius, yRadius: radius)
clip.addClip()

NSGradient(colors: [
    NSColor(srgbRed: 0.13, green: 0.18, blue: 0.32, alpha: 1),
    NSColor(srgbRed: 0.05, green: 0.08, blue: 0.15, alpha: 1),
])?.draw(in: inset, angle: -55)

// 网格点(细弱装饰)
NSColor.white.withAlphaComponent(0.05).setFill()
for gx in stride(from: inset.minX + 80, to: inset.maxX, by: 132) {
    for gy in stride(from: inset.minY + 80, to: inset.maxY, by: 132) {
        NSBezierPath(ovalIn: NSRect(x: gx, y: gy, width: 6, height: 6)).fill()
    }
}

// 上升折线
let linePoints: [CGPoint] = [
    CGPoint(x: inset.minX + 90, y: inset.minY + 250),
    CGPoint(x: inset.minX + 300, y: inset.minY + 420),
    CGPoint(x: inset.minX + 460, y: inset.minY + 360),
    CGPoint(x: inset.minX + 640, y: inset.minY + 560),
    CGPoint(x: inset.minX + 740, y: inset.minY + 520),
]
let line = NSBezierPath()
line.lineWidth = 30
line.lineCapStyle = .round
line.lineJoinStyle = .round
for (index, point) in linePoints.enumerated() {
    if index == 0 { line.move(to: point) } else { line.line(to: point) }
}

// 折线下方渐变填充
if let areaGradient = NSGradient(colors: [
    NSColor(srgbRed: 0.16, green: 0.80, blue: 0.55, alpha: 0.30),
    NSColor(srgbRed: 0.16, green: 0.80, blue: 0.55, alpha: 0.0),
]) {
    let area = line.copy() as! NSBezierPath
    area.line(to: CGPoint(x: linePoints.last!.x, y: inset.minY + 40))
    area.line(to: CGPoint(x: linePoints.first!.x, y: inset.minY + 40))
    area.close()
    areaGradient.draw(in: area, angle: -90)
}

// 主折线:白色
NSColor.white.setStroke()
line.stroke()

// 终点圆点:红(涨)
let last = linePoints.last!
NSColor(srgbRed: 1.0, green: 0.36, blue: 0.36, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: last.x - 34, y: last.y - 34, width: 68, height: 68)).fill()
NSColor.white.setFill()
NSBezierPath(ovalIn: NSRect(x: last.x - 14, y: last.y - 14, width: 28, height: 28)).fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("图标渲染失败\n", stderr)
    exit(1)
}
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
try? png.write(to: URL(fileURLWithPath: output))
print("图标已生成:\(output)")
