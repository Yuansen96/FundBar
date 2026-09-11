import SwiftUI

/// 点开菜单栏图标后的主面板:大盘 / 板块 / 我的基金 三个页签,
/// 右上角齿轮进入设置;添加基金和基金详情以子页面方式呈现。
struct PanelView: View {
    private enum Page: Equatable {
        case tabs
        case addFund
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
                AddFundPage { page = .tabs; tab = 2 }
            case .settings:
                SettingsPage { page = .tabs }
            case .detail(let code):
                FundDetailPage(code: code) { page = .tabs; tab = 2 }
            }
        }
        .frame(width: 440)
        .task { await MarketStore.shared.refreshIfNeeded() }
    }

    @ViewBuilder
    private var tabsContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("FundBar")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
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
                        onOpenDetail: { code in page = .detail(code) }
                    )
                }
            }
            .frame(minHeight: 420, maxHeight: 540)

            Divider()
            MarketFooterView()
        }
    }
}

/// 面板底部:错误信息 / 最后更新时间 / 手动刷新
struct MarketFooterView: View {
    @ObservedObject private var store = MarketStore.shared

    var body: some View {
        HStack(spacing: 8) {
            if let error = store.errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if let date = store.lastUpdated {
                Text("更新于 \(date.formatted(.dateTime.hour().minute().second()))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text("尚未加载")
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
