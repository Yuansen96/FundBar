import SwiftUI
import ServiceManagement

/// 设置页:菜单栏显示模式、菜单栏指数(最多 3 个)、刷新间隔、关于
struct SettingsPage: View {
    var onBack: () -> Void

    @State private var launchAtLoginError: String?

    @AppStorage(SettingsKey.menuBarMode) private var menuBarMode = "icon"
    @AppStorage(SettingsKey.menuBarCodes) private var codesRaw = "1.000001"
    @AppStorage(SettingsKey.refreshInterval) private var refreshInterval = 60.0
    @AppStorage(SettingsKey.alertEnabled) private var alertEnabled = false
    @AppStorage(SettingsKey.alertThreshold) private var alertThreshold = 2.0
    @AppStorage(SettingsKey.dataSource) private var dataSourceRaw = DataSourceMode.auto.rawValue
    @AppStorage(SettingsKey.icloudSyncEnabled) private var icloudSync = true
    @ObservedObject private var store = MarketStore.shared
    @ObservedObject private var sync = SyncService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                Text("设置")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("菜单栏显示", selection: $menuBarMode) {
                                Text("仅图标").tag("icon")
                                Text("图标 + 指数涨跌").tag("iconText")
                            }
                            Text("摘要为彩色实时渲染(红涨绿跌);点击状态项展开面板可查看完整行情。")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(4)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("行情数据源", selection: $dataSourceRaw) {
                                ForEach(DataSourceMode.allCases) { mode in
                                    Text(mode.label).tag(mode.rawValue)
                                }
                            }
                            .onChange(of: dataSourceRaw) { _ in
                                store.applyDataSourceSetting()
                            }
                            Text("自动:东财优先,失败(如 IPv6 异常网络)自动切换腾讯备用源。日经225 / KOSPI 与板块榜仅东财提供。")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(4)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("菜单栏摘要指数(最多选 3 个)")
                                .font(.callout)
                                .fontWeight(.medium)
                            ForEach(IndexDef.all) { def in
                                indexToggle(def)
                            }
                        }
                        .padding(4)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("刷新间隔", selection: $refreshInterval) {
                                Text("30 秒").tag(30.0)
                                Text("1 分钟").tag(60.0)
                                Text("5 分钟").tag(300.0)
                            }
                            .onChange(of: refreshInterval) {
                                store.startTimer()
                            }
                        }
                        .padding(4)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("涨跌提醒通知", isOn: $alertEnabled)
                                .onChange(of: alertEnabled) {
                                    if alertEnabled {
                                        NotificationManager.shared.requestAuthorization()
                                        // 把当前档位落盘,避免未交互过时阈值读取为 0
                                        UserDefaults.standard.set(alertThreshold, forKey: SettingsKey.alertThreshold)
                                    }
                                }
                            if alertEnabled {
                                Picker("提醒阈值", selection: $alertThreshold) {
                                    Text("±1%").tag(1.0)
                                    Text("±2%").tag(2.0)
                                    Text("±3%").tag(3.0)
                                    Text("±5%").tag(5.0)
                                }
                                Text("持仓基金当日涨跌幅越过阈值时发送系统通知,每只基金每天最多提醒一次。")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(4)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            switch sync.availability {
                            case .available:
                                Toggle("iCloud 同步持仓与设置", isOn: $icloudSync)
                                    .onChange(of: icloudSync) {
                                        UserDefaults.standard.set(icloudSync, forKey: SettingsKey.icloudSyncEnabled)
                                        if icloudSync { sync.pushIfNeeded() }
                                    }
                                if let last = sync.lastSyncedAt {
                                    Text("上次同步 \(last.formatted(.dateTime.month().day().hour().minute()))")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                Text("数据写入 iCloud Drive/FundBar/,同一 Apple ID 的其他 Mac 自动互相同步(新时间戳整体覆盖)。")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            case .checking:
                                Text("正在检查 iCloud Drive…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            case .unavailable(let reason):
                                Text("iCloud 同步不可用:\(reason)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(4)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(
                                "登录时自动启动",
                                isOn: Binding(
                                    get: { SMAppService.mainApp.status == .enabled },
                                    set: { newValue in
                                        launchAtLoginError = nil
                                        do {
                                            if newValue {
                                                try SMAppService.mainApp.register()
                                            } else {
                                                try SMAppService.mainApp.unregister()
                                            }
                                        } catch {
                                            launchAtLoginError = "设置失败:\(error.localizedDescription)"
                                        }
                                    }
                                )
                            )
                            if let launchAtLoginError {
                                Text(launchAtLoginError)
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(4)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("关于 FundBar")
                                .font(.callout)
                                .fontWeight(.medium)
                            Text("版本 0.7.0 · SwiftUI 原生 macOS 菜单栏基金行情工具")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("数据来源:东方财富、蛋卷基金公开接口(非官方,无可用性保证)。本项目仅供学习交流,不构成任何投资建议。")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(4)
                    }
                }
            }
            Spacer()
        }
        .padding(14)
    }

    private var selectedCodes: Set<String> {
        Set(codesRaw.split(separator: ",").map(String.init))
    }

    private func indexToggle(_ def: IndexDef) -> some View {
        let isOn = selectedCodes.contains(def.secid)
        return Toggle(def.name, isOn: Binding(
            get: { isOn },
            set: { newValue in
                var codes = selectedCodes
                if newValue {
                    guard codes.count < 3, !codes.contains(def.secid) else { return }
                    codes.insert(def.secid)
                } else {
                    guard codes.count > 1 else { return } // 至少保留一个
                    codes.remove(def.secid)
                }
                var ordered = IndexDef.all.map(\.secid).filter { codes.contains($0) }
                if ordered.isEmpty { ordered = ["1.000001"] }
                codesRaw = ordered.joined(separator: ",")
            }
        ))
        .font(.system(size: 12.5))
    }
}
