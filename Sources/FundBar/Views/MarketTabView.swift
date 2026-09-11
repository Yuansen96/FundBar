import SwiftUI

/// 大盘页签:按 A股 / 亚太 / 美股 分组展示 9 个指数,卡片化行 + 渐变涨跌胶囊
struct MarketTabView: View {
    @ObservedObject private var store = MarketStore.shared

    private static let regionFlags: [IndexRegion: String] = [
        .cn: "🇨🇳", .asia: "🌏", .us: "🇺🇸",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                if store.indexQuotes.isEmpty {
                    emptyState
                }
                ForEach(IndexRegion.allCases) { region in
                    let quotes = store.indexQuotes.filter { $0.def.region == region }
                    if !quotes.isEmpty {
                        regionHeader(region)
                        ForEach(quotes) { quote in
                            IndexRow(quote: quote)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            if store.isLoading {
                ProgressView()
            } else {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 26))
                    .foregroundStyle(.tertiary)
                Text(store.errorMessage ?? "暂无数据,点击下方刷新")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }

    private func regionHeader(_ region: IndexRegion) -> some View {
        HStack(spacing: 5) {
            Text(Self.regionFlags[region] ?? "🌐")
                .font(.system(size: 11))
            Text(region.rawValue)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
        .padding(.leading, 2)
    }
}

struct IndexRow: View {
    let quote: IndexQuote
    @State private var hovered = false

    private var isUnavailable: Bool {
        quote.price == nil && quote.changePercent == nil
    }

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(CnStyle.color(for: quote.changePercent).opacity(0.75))
                .frame(width: 3, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(quote.def.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(quote.def.secid)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()

            if isUnavailable {
                Text("当前网络暂不可用")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                Text(quote.price?.priceText ?? "--")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .frame(minWidth: 62, alignment: .trailing)
                Text(quote.change?.changeText ?? "--")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(CnStyle.color(for: quote.changePercent))
                    .frame(width: 58, alignment: .trailing)
                changePill
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.primary.opacity(hovered ? 0.07 : 0.03))
        )
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }

    /// 白字彩底渐变胶囊
    private var changePill: some View {
        let color = CnStyle.color(for: quote.changePercent)
        return Text(quote.changePercent?.percentText ?? "--")
            .font(.system(size: 11.5, weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(
                    LinearGradient(
                        colors: [color.opacity(0.9), color.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            )
            .frame(width: 70, alignment: .trailing)
    }
}
