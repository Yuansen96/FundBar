import SwiftUI

/// 设置页:菜单栏显示模式、菜单栏指数(最多 3 个)、刷新间隔、关于
struct SettingsPage: View {
    var onBack: () -> Void

    @AppStorage(SettingsKey.menuBarMode) private var menuBarMode = "icon"
    @AppStorage(SettingsKey.menuBarCodes) private var codesRaw = "1.000001"
    @AppStorage(SettingsKey.refreshInterval) private var refreshInterval = 60.0
    @ObservedObject private var store = MarketStore.shared

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
                            Text("系统状态栏只支持单色文字,红绿配色在面板内展示;展开面板可查看完整行情。")
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
                        VStack(alignment: .leading, spacing: 6) {
                            Text("关于 FundBar")
                                .font(.callout)
                                .fontWeight(.medium)
                            Text("版本 0.1.0 · SwiftUI 原生 macOS 菜单栏基金行情工具")
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
