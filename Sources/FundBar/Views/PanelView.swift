import SwiftUI

/// 点开菜单栏图标后的主面板:大盘 / 板块 / 我的基金 三个页签,
/// 毛玻璃材质背景;添加/编辑基金和详情以子页面方式呈现。
struct PanelView: View {
    private enum Page: Equatable {
        case tabs
        case addFund
        case editFund(Holding)
        case settings
        case detail(String)
    }

    @State private var tab = 0
    @State private var page: Page = .tabs

    var body: some View {
        Group {
            switch page {
            case .tabs:
                tabsContent
            case .addFund:
                AddFundPage(editing: nil) { page = .tabs; tab = 2 }
            case .editFund(let holding):
                AddFundPage(editing: holding) { page = .tabs; tab = 2 }
            case .settings:
                SettingsPage { page = .tabs }
            case .detail(let code):
                FundDetailPage(code: code) { page = .tabs; tab = 2 }
            }
        }
        .frame(width: 460)
        .background(.regularMaterial)
        .task { await MarketStore.shared.refreshIfNeeded() }
    }

    @ViewBuilder
    private var tabsContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("FundBar")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [CnStyle.up, CnStyle.down],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                Picker("", selection: $tab) {
                    Text("大盘").tag(0)
                    Text("板块").tag(1)
                    Text("我的基金").tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 240)
                Spacer()
                Button {
                    page = .settings
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .help("设置")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            Group {
                switch tab {
                case 0:
                    MarketTabView()
                case 1:
                    SectorTabView()
                default:
                    FundTabView(
                        onAdd: { page = .addFund },
                        onEdit: { holding in page = .editFund(holding) },
                        onOpenDetail: { code in page = .detail(code) }
                    )
                }
            }
            .frame(minHeight: 430, maxHeight: 560)
            .animation(.easeInOut(duration: 0.16), value: tab)

            Divider()
            MarketFooterView()
        }
    }
}

/// 面板底部:状态点 + 三态信息(错误 / 降级 / 正常)+ 手动刷新
struct MarketFooterView: View {
    @ObservedObject private var store = MarketStore.shared

    private var dotColor: Color {
        if store.errorMessage != nil { return .red }
        if store.dataSourceNote != nil { return .yellow }
        return store.lastUpdated != nil ? .green : .gray
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
            if let error = store.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            } else if let note = store.dataSourceNote {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .help(note)
            } else if let date = store.lastUpdated {
                Text("已连接 · 更新于 \(date.formatted(.dateTime.hour().minute().second()))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text("尚未连接")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if store.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                Task { await store.refresh(showLoading: false) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("立即刷新")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
