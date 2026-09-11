import SwiftUI

@main
struct FundBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            PanelView()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 菜单栏小工具:不出现在 Dock 和程序切换器
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}

/// 菜单栏状态项:默认仅一个小图标,点击展开面板看行情;
/// 可在设置中切换为「图标 + 指数涨跌摘要」(最多 3 个指数,系统状态栏限制为单色文字)。
struct MenuBarLabel: View {
    @AppStorage(SettingsKey.menuBarMode) private var mode = "icon"
    @AppStorage(SettingsKey.menuBarCodes) private var codesRaw = "1.000001"
    @ObservedObject private var store = MarketStore.shared

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "chart.line.uptrend.xyaxis")
            if mode == "iconText" {
                ForEach(Array(selectedQuotes.prefix(3)), id: \.id) { quote in
                    summaryText(quote)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                }
            }
        }
    }

    private var selectedQuotes: [IndexQuote] {
        let codes = codesRaw.split(separator: ",").map(String.init)
        return codes.compactMap { code in
            store.indexQuotes.first { $0.def.secid == code }
        }
    }

    private func summaryText(_ quote: IndexQuote) -> Text {
        guard let percent = quote.changePercent else {
            return Text(quote.def.shortName)
        }
        return Text("\(quote.def.shortName) \(percent.percentText)")
    }
}
