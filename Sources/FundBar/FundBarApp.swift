import SwiftUI
import AppKit
import Combine

@main
struct FundBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 真实 UI 由 AppDelegate 的 NSStatusItem + NSPopover 驱动;
        // 不用 MenuBarExtra 是因为其 label 不响应运行时状态变化(系统限制)。
        Settings { }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 菜单栏小工具:不出现在 Dock 和程序切换器
        NSApplication.shared.setActivationPolicy(.accessory)
        NotificationManager.shared.installPresentationDelegate()

        setupStatusItem()
        setupPopover()
        observeUpdates()
        updateStatusItem()
        SyncService.shared.start()
    }

    // MARK: - 状态项与弹窗

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "chart.line.uptrend.xyaxis",
                accessibilityDescription: "FundBar"
            )
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        statusItem = item
    }

    private func setupPopover() {
        popover.contentSize = NSSize(width: 460, height: 560)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: PanelView())
    }

    /// 行情数据或设置变化时刷新状态项显示
    private func observeUpdates() {
        MarketStore.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // objectWillChange 在变更前发出,延迟到下一轮读取新值
                Task { @MainActor in self?.updateStatusItem() }
            }
            .store(in: &cancellables)
        NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let defaults = UserDefaults.standard
        let mode = defaults.string(forKey: SettingsKey.menuBarMode) ?? "icon"
        let codes = (defaults.string(forKey: SettingsKey.menuBarCodes) ?? "1.000001")
            .split(separator: ",")
            .map(String.init)

        if mode == "iconText" {
            let quotes = codes.prefix(3).compactMap { code in
                MarketStore.shared.indexQuotes.first { $0.def.secid == code }
            }
            button.attributedTitle = MenuBarSummaryRenderer.attributedText(for: quotes)
        } else {
            button.attributedTitle = NSAttributedString()
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
