import AppKit
import SwiftUI

// README 截图生成器:离屏窗口渲染真实视图(含真实行情数据)并输出 PNG
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

// 1) 主面板(大盘页签,含 sparkline)
let panelWindow = makeWindow(
    rootView: AnyView(
        PanelView()
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    ),
    size: NSSize(width: 460, height: 580)
)
spinRunLoop(seconds: 14) // 等 indices/sparklines 加载完成
if let rep = snapshot(window: panelWindow) {
    writePNG(rep, to: "screenshot-panel.png")
}
panelWindow.orderOut(nil)

// 2) 基金详情(净值走势 + 阶段涨幅);注入演示持仓让统计卡有内容
Task { @MainActor in
    MarketStore.shared.addOrUpdateHolding(Holding(code: "161725", name: "招商中证白酒指数A", amount: 10000, cost: 11820))
    await MarketStore.shared.refresh(showLoading: false)
}
let detailWindow = makeWindow(
    rootView: AnyView(
        FundDetailPage(code: "161725", onBack: {})
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    ),
    size: NSSize(width: 460, height: 620)
)
spinRunLoop(seconds: 12) // 等蛋卷详情 + 历史净值(3 页)加载
if let rep = snapshot(window: detailWindow) {
    writePNG(rep, to: "screenshot-detail.png")
}
detailWindow.orderOut(nil)

exit(0)
