import SwiftUI

/// 板块页签:行业板块涨跌幅双榜,行内带涨跌幅比例条
struct SectorTabView: View {
    @ObservedObject private var store = MarketStore.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let error = store.sectorError {
                    unavailableCard(error)
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        rankCard(title: "▲ 涨幅榜", quotes: store.sectorGainers)
                        rankCard(title: "▼ 跌幅榜", quotes: store.sectorLosers)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func unavailableCard(_ error: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("板块榜由东方财富源提供,指数行情不受影响")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding()
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func rankCard(title: String, quotes: [SectorQuote]) -> some View {
        let maxAbs = quotes.compactMap { $0.changePercent.map(abs) }.max() ?? 1

        return VStack(alignment: .leading, spacing: 0) {
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
                sectorRow(sector, maxAbs: maxAbs)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .frame(maxWidth: .infinity)
    }

    private func sectorRow(_ sector: SectorQuote, maxAbs: Double) -> some View {
        let color = CnStyle.color(for: sector.changePercent)
        let ratio = sector.changePercent.map { min(abs($0) / max(maxAbs, 0.01), 1) } ?? 0

        return HStack(spacing: 6) {
            Text(sector.name)
                .font(.system(size: 12.5))
                .lineLimit(1)
            Spacer(minLength: 4)
            GeometryReader { proxy in
                Capsule()
                    .fill(color.opacity(0.65))
                    .frame(width: max(3, proxy.size.width * ratio), height: 4)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .frame(height: proxy.size.height)
                    .animation(.easeOut(duration: 0.25), value: ratio)
            }
            .frame(width: 44, height: 12)
            Text(sector.changePercent?.percentText ?? "--")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(color)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.vertical, 4.5)
        .padding(.horizontal, 6)
        .background(Color.primary.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
