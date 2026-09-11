import SwiftUI

/// 大盘页签:按 A股 / 亚太 / 美股 分组展示全部 9 个指数
struct MarketTabView: View {
    @ObservedObject private var store = MarketStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                if store.indexQuotes.isEmpty && store.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else if store.indexQuotes.isEmpty {
                    Text(store.errorMessage ?? "暂无数据,点击下方刷新")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 240)
                }
                ForEach(IndexRegion.allCases) { region in
                    let quotes = store.indexQuotes.filter { $0.def.region == region }
                    if !quotes.isEmpty {
                        Text(region.rawValue)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.bottom, 2)
                            .padding(.leading, 2)
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
}

struct IndexRow: View {
    let quote: IndexQuote

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(quote.def.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(quote.def.secid)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text(quote.price?.priceText ?? "--")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .frame(minWidth: 64, alignment: .trailing)
            Text(quote.change?.changeText ?? "--")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(CnStyle.color(for: quote.changePercent))
                .frame(width: 60, alignment: .trailing)
            Text(quote.changePercent?.percentText ?? "--")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(CnStyle.color(for: quote.changePercent))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(CnStyle.color(for: quote.changePercent).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(Color.primary.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
