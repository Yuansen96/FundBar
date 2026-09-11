import SwiftUI

/// 板块页签:行业板块涨跌幅双榜(东财 fs=m:90+t:2)
struct SectorTabView: View {
    @ObservedObject private var store = MarketStore.shared

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 12) {
                rankCard(title: "▲ 涨幅榜", quotes: store.sectorGainers)
                rankCard(title: "▼ 跌幅榜", quotes: store.sectorLosers)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func rankCard(title: String, quotes: [SectorQuote]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)
            if quotes.isEmpty {
                Text("加载中…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            }
            ForEach(quotes) { sector in
                HStack {
                    Text(sector.name)
                        .font(.system(size: 12.5))
                        .lineLimit(1)
                    Spacer()
                    Text(sector.changePercent?.percentText ?? "--")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(CnStyle.color(for: sector.changePercent))
                }
                .padding(.vertical, 4.5)
                .padding(.horizontal, 6)
                .background(Color.primary.opacity(0.025))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}
