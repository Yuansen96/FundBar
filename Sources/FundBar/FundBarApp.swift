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
        NotificationManager.shared.installPresentationDelegate()
    }
}

/// 菜单栏状态项:默认仅一个小图标,点击展开面板看行情;
/// 「图标+涨跌摘要」模式把文字离屏绘制成彩色 NSImage(系统模板渲染不支持彩色文字)。
struct MenuBarLabel: View {
    @AppStorage(SettingsKey.menuBarMode) private var mode = "icon"
    @AppStorage(SettingsKey.menuBarCodes) private var codesRaw = "1.000001"
    @ObservedObject private var store = MarketStore.shared

    var body: some View {
        Group {
            if mode == "iconText", let image = MenuBarSummaryRenderer.render(selectedQuotes) {
                HStack(spacing: 4) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                    Image(nsImage: image)
                        .renderingMode(.original)
                        .padding(.horizontal, 3)
                }
            } else {
                Image(systemName: "chart.line.uptrend.xyaxis")
            }
        }
    }

    private var selectedQuotes: [IndexQuote] {
        let codes = codesRaw.split(separator: ",").map(String.init)
        return codes.compactMap { code in
            store.indexQuotes.first { $0.def.secid == code }
        }
    }
}
