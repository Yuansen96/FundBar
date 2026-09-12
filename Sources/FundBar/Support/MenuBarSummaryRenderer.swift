import AppKit

/// 菜单栏状态项的彩色涨跌摘要:NSStatusItem 的 attributedTitle 原生支持彩色文字,
/// 名称用系统默认色(自动适配明暗菜单栏),涨跌幅红涨绿跌。
enum MenuBarSummaryRenderer {
    static func attributedText(for quotes: [IndexQuote]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let nameAttributes: [NSAttributedString.Key: Any] = [.font: font]

        var index = 0
        for quote in quotes {
            guard let percent = quote.changePercent else { continue }
            if index > 0 {
                result.append(NSAttributedString(string: "   ", attributes: nameAttributes))
            }
            result.append(NSAttributedString(string: "\(quote.def.shortName) ", attributes: nameAttributes))
            result.append(
                NSAttributedString(
                    string: percent.percentText,
                    attributes: [
                        .font: font,
                        .foregroundColor: percent >= 0 ? Self.up : Self.down,
                    ]
                )
            )
            index += 1
        }
        return result
    }

    private static let up = NSColor(srgbRed: 1.0, green: 0.36, blue: 0.36, alpha: 1)
    private static let down = NSColor(srgbRed: 0.16, green: 0.8, blue: 0.55, alpha: 1)
}
