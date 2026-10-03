import AppKit
import SwiftUI

// README 截图生成器:离屏窗口渲染真实视图与固定示例数据,不访问网络或用户持仓
// 用法:make-screenshots <输出目录>   (在仓库根目录运行)

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

func makeWindow(rootView: AnyView, size: NSSize) -> NSWindow {
    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.backgroundColor = .clear
    let host = NSHostingView(rootView: rootView)
    host.frame = NSRect(origin: .zero, size: size)
    window.contentView = host
    window.orderFrontRegardless()
    return window
}

func spinRunLoop(seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
}

func snapshot(window: NSWindow) -> NSBitmapImageRep? {
    guard let contentView = window.contentView else { return nil }
    contentView.wantsLayer = true
    contentView.layoutSubtreeIfNeeded()
    let bounds = contentView.bounds
    let scale: CGFloat = 2
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(bounds.width * scale),
        pixelsHigh: Int(bounds.height * scale),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }
    rep.size = bounds.size
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    cg.translateBy(x: 0, y: rep.size.height)
    cg.scaleBy(x: 1, y: -1)
    contentView.layer?.render(in: cg)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to name: String) {
    guard let png = rep.representation(using: .png, properties: [:]) else { return }
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    try? png.write(to: url)
    print("已生成:\(url.path) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
}

// 固定样本保证离线生成结果稳定,README 中明确标明示例数据。
let samples: [(Double, Double, Double)] = [
    (3888.11, -46.29, -1.18), (13471.36, -146.41, -1.08), (3322.04, -16.38, -0.49),
    (24805.63, -148.83, -0.60), (64011.34, -1259.61, -1.93), (6909.91, -124.01, -1.76),
    (52573.29, 509.19, 0.98), (26333.04, 251.32, 0.96), (7656.98, 65.28, 0.86),
]
let previewIndices = zip(IndexDef.all, samples).map { def, sample in
    IndexQuote(def: def, price: sample.0, change: sample.1, changePercent: sample.2, dataDate: "2026-09-11")
}
var previewSparklines: [String: [Double]] = [:]
for (offset, def) in IndexDef.all.enumerated() {
    let slope = offset < 6 ? -0.12 : 0.12
    var values: [Double] = []
    for index in 0..<20 {
        let progress = Double(index)
        let wave = sin(progress * 0.8 + Double(offset)) * 0.45
        values.append(10.0 + slope * progress + wave)
    }
    previewSparklines[def.secid] = values
}

// 1) 主面板(大盘页签,含 sparkline)
let panelWindow = makeWindow(
    rootView: AnyView(
        PanelView(
            previewIndices: previewIndices,
            previewSparklines: previewSparklines,
            previewNotice: "示例行情 · 仅用于界面展示"
        )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    ),
    size: NSSize(width: 460, height: 560)
)
spinRunLoop(seconds: 1)
if let rep = snapshot(window: panelWindow) {
    writePNG(rep, to: "screenshot-panel.png")
}
panelWindow.orderOut(nil)

// 2) 基金详情(净值走势 + 阶段涨幅);预览持仓不写入用户数据
let dayFormatter = DateFormatter()
dayFormatter.dateFormat = "yyyy-MM-dd"
let lastDay = dayFormatter.date(from: "2026-09-11")!
let previewHistory = (0..<30).map { index -> NavPoint in
    let date = Calendar.current.date(byAdding: .day, value: index - 29, to: lastDay)!
    let value = index == 29 ? 0.5337 : 0.58 - Double(index) * 0.0015 + sin(Double(index) * 0.6) * 0.005
    return NavPoint(date: dayFormatter.string(from: date), nav: value, changePercent: nil)
}
let previewDetail = FundDetail(
    code: "161725", name: "招商中证白酒指数A", unitNav: 0.5337,
    navDate: "2026-09-11", dayChangePercent: -1.51,
    stageReturns: [
        StageReturn(label: "近1月", percent: -6.74), StageReturn(label: "近3月", percent: -2.15),
        StageReturn(label: "近6月", percent: -18.94), StageReturn(label: "近1年", percent: -36.31),
    ]
)
let detailWindow = makeWindow(
    rootView: AnyView(
        FundDetailPage(
            code: "161725",
            onBack: {},
            previewHolding: Holding(code: "161725", name: "招商中证白酒指数A", amount: 10000, cost: 11820),
            previewDetail: previewDetail,
            previewHistory: previewHistory
        )
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    ),
    size: NSSize(width: 460, height: 560)
)
spinRunLoop(seconds: 1)
if let rep = snapshot(window: detailWindow) {
    writePNG(rep, to: "screenshot-detail.png")
}
detailWindow.orderOut(nil)

// 3) 持仓页：排序入口与每行编辑按钮；只读注入样本，不写入本机持仓。
let previewHoldings = [
    Holding(code: "161725", name: "招商中证白酒指数A", amount: 10000, cost: 11820),
    Holding(code: "000217", name: "华安黄金C", amount: 36000, cost: 34000),
    Holding(code: "110022", name: "易方达消费行业", amount: 8000, cost: 9500),
    Holding(code: "005827", name: "易方达蓝筹精选", amount: 13500, cost: 11000),
]
let holdingsWindow = makeWindow(
    rootView: AnyView(
        FundTabView(
            onAdd: {}, onEdit: { _ in }, onOpenDetail: { _ in },
            previewHoldings: previewHoldings,
            previewPercents: ["161725": -1.51, "000217": 0.42, "110022": -0.75, "005827": 1.32]
        )
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    ),
    size: NSSize(width: 460, height: 560)
)
spinRunLoop(seconds: 1)
if let rep = snapshot(window: holdingsWindow) {
    writePNG(rep, to: "screenshot-holdings.png")
}
holdingsWindow.orderOut(nil)

exit(0)
