import SwiftUI

/// 我的基金页签:渐变盈亏横幅 + 持仓列表;行支持编辑/删除,点击查看走势
struct FundTabView: View {
    @ObservedObject private var store = MarketStore.shared
    let onAdd: () -> Void
    let onEdit: (Holding) -> Void
    let onOpenDetail: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 5) {
                if store.holdings.isEmpty {
                    emptyState
                } else {
                    summaryBanner
                    headerRow
                    ForEach(store.holdings) { holding in
                        let percentInfo = store.effectivePercent(for: holding.code)
                        FundRow(
                            holding: holding,
                            dayPercent: percentInfo?.percent,
                            isEstimate: percentInfo?.isEstimate ?? false
                        ) {
                            onOpenDetail(holding.code)
                        }
                        .contextMenu {
                            Button("编辑持有金额") { onEdit(holding) }
                            Divider()
                            Button("删除", role: .destructive) {
                                store.removeHolding(code: holding.code)
                            }
                        }
                    }
                }
                Button(action: onAdd) {
                    Label(store.holdings.isEmpty ? "添加基金(代码 + 持有金额)" : "添加基金", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    // MARK: - 盈亏汇总横幅

    private var summaryTotals: (amount: Double, dayPnl: Double, totalPnl: Double?, totalPnlPercent: Double?) {
        var amount = 0.0
        var dayPnl = 0.0
        var cost = 0.0
        var hasCost = false
        for holding in store.holdings {
            let percent = store.effectivePercent(for: holding.code)?.percent ?? 0
            amount += holding.amount
            dayPnl += Holding.dayPnl(amount: holding.amount, dayPercent: percent)
            if let holdingCost = holding.cost, holdingCost > 0 {
                cost += holdingCost
                hasCost = true
            }
        }
        let totalPnl: Double? = hasCost ? amount + dayPnl - cost : nil
        let totalPnlPercent: Double? = hasCost ? totalPnl.map { $0 / cost * 100 } : nil
        return (amount, dayPnl, totalPnl, totalPnlPercent)
    }

    private var summaryBanner: some View {
        let totals = summaryTotals
        let dayColor = CnStyle.color(for: totals.dayPnl)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("今日盈亏")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(totals.amount.yuanText)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(totals.dayPnl.yuanText)
                    .font(.system(size: 26, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(dayColor)
                if let percent = totals.totalPnlPercent {
                    Text("持有 \(percent.percentText)")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(CnStyle.color(for: percent))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(CnStyle.color(for: percent).opacity(0.12))
                        .clipShape(Capsule())
                }
                Spacer()
            }
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [dayColor.opacity(0.16), dayColor.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(dayColor.opacity(0.15), lineWidth: 1)
        )
        .padding(.bottom, 4)
    }

    // MARK: - 列表

    private var headerRow: some View {
        HStack {
            Text("基金").font(.caption2).foregroundStyle(.tertiary)
            Spacer()
            Text("今日").font(.caption2).foregroundStyle(.tertiary).frame(width: 52, alignment: .trailing)
            Text("持有金额").font(.caption2).foregroundStyle(.tertiary).frame(width: 62, alignment: .trailing)
            Text("当日盈亏").font(.caption2).foregroundStyle(.tertiary).frame(width: 62, alignment: .trailing)
            Text("持有收益").font(.caption2).foregroundStyle(.tertiary).frame(width: 76, alignment: .trailing)
        }
        .padding(.horizontal, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("还没有添加基金")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("输入基金代码和持有金额,即可跟踪当日涨跌与盈亏")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}

struct FundRow: View {
    let holding: Holding
    let dayPercent: Double?
    var isEstimate = false
    let onOpen: () -> Void
    @State private var hovered = false

    var body: some View {
        let dayPnl = Holding.dayPnl(amount: holding.amount, dayPercent: dayPercent ?? 0)
        let totalPnl = Holding.totalPnl(amount: holding.amount, dayPercent: dayPercent ?? 0, cost: holding.cost)
        let totalPercent = Holding.totalPnlPercent(amount: holding.amount, dayPercent: dayPercent ?? 0, cost: holding.cost)

        return Button(action: onOpen) {
            HStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(CnStyle.color(for: dayPercent).opacity(0.75))
                    .frame(width: 3, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(holding.name)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        if isEstimate {
                            Text("估")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(Color.orange.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    Text("\(holding.code) · 点击看走势")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text(dayPercent?.percentText ?? "--")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(CnStyle.color(for: dayPercent))
                    .frame(width: 52, alignment: .trailing)
                Text(holding.amount.yuanText)
                    .font(.system(size: 12).monospacedDigit())
                    .frame(width: 62, alignment: .trailing)
                Text(dayPnl.yuanText)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(CnStyle.color(for: dayPnl))
                    .frame(width: 62, alignment: .trailing)
                Group {
                    if let totalPnl {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(totalPnl.yuanText)
                                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            Text(totalPercent?.percentText ?? "")
                                .font(.caption2)
                        }
                        .foregroundStyle(CnStyle.color(for: totalPnl))
                    } else {
                        Text("--")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 76, alignment: .trailing)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.primary.opacity(hovered ? 0.07 : 0.03))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}
