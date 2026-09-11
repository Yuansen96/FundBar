import AppKit

/// 菜单栏状态项的彩色涨跌摘要:系统状态栏模板渲染不支持彩色文字,
/// 把「上证 -1.18% · 纳指 +1.24%」离屏绘制成 NSImage,以 .original 模式显示。
enum MenuBarSummaryRenderer {
    static func render(_ quotes: [IndexQuote]) -> NSImage? {
        var segments: [(text: String, color: NSColor)] = []
        var index = 0
        for quote in quotes {
            guard let percent = quote.changePercent else { continue }
            if index > 0 { segments.append(("   ", NSColor.labelColor)) }
            segments.append(("\(quote.def.shortName) ", nameColor()))
            segments.append((percent.percentText, percent >= 0 ? Self.nsUp : Self.nsDown))
            index += 1
        }
        guard !segments.isEmpty else { return nil }

        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let metricsAttributes: [NSAttributedString.Key: Any] = [.font: font]
        let totalWidth = segments.reduce(CGFloat(0)) {
            $0 + ($1.text as NSString).size(withAttributes: metricsAttributes).width
        }
        let size = NSSize(width: ceil(totalWidth) + 2, height: 14)

        return NSImage(size: size, flipped: false) { _ in
            var drawX: CGFloat = 0
            for segment in segments {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: segment.color,
                ]
                (segment.text as NSString).draw(at: NSPoint(x: drawX, y: 1), withAttributes: attributes)
                drawX += (segment.text as NSString).size(withAttributes: metricsAttributes).width
            }
            return true
        }
    }

    /// 名称颜色跟随系统外观(菜单栏与应用外观一致)
    private static func nameColor() -> NSColor {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark ? .white : .black
    }

    private static let nsUp = NSColor(srgbRed: 1.0, green: 0.36, blue: 0.36, alpha: 1)
    private static let nsDown = NSColor(srgbRed: 0.16, green: 0.8, blue: 0.55, alpha: 1)
}
