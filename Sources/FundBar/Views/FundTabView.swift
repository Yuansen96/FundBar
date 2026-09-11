import SwiftUI

/// 我的基金页签:持仓列表 + 盈亏汇总。
/// 每行显示:今日涨跌、持有金额、当日盈亏、持有收益;点击行查看走势详情。
struct FundTabView: View {
    @ObservedObject private var store = MarketStore.shared
    let onAdd: () -> Void
    let onOpenDetail: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                summaryBar
                if store.holdings.isEmpty {
                    emptyState
                } else {
                    headerRow
                    ForEach(store.holdings) { holding in
                        FundRow(
                            holding: holding,
                            dayPercent: store.dayPercent(for: holding.code)
                        ) {
                            onOpenDetail(holding.code)
                        }
                        .contextMenu {
                            Button("删除", role: .destructive) {
                                store.removeHolding(code: holding.code)
                            }
                        }
                    }
                }
                Button(action: onAdd) {
                    Label("添加基金(代码 + 持有金额)", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 10)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    // MARK: - 盈亏汇总

    private var summaryBar: some View {
        let totals = summaryTotals
        return HStack(spacing: 16) {
            statBlock(title: "总持有", value: totals.amount.yuanText, color: .primary)
            statBlock(title: "今日盈亏", value: totals.dayPnl.yuanText, color: CnStyle.color(for: totals.dayPnl))
            statBlock(
                title: "持有收益",
                value: totals.totalPnl.map(\.yuanText) ?? "填写成本后显示",
                color: totals.totalPnl.map { CnStyle.color(for: $0) } ?? .secondary
            )
            if let percent = totals.totalPnlPercent {
                Text(percent.percentText)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(CnStyle.color(for: percent))
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.bottom, 6)
    }

    private var summaryTotals: (amount: Double, dayPnl: Double, totalPnl: Double?, totalPnlPercent: Double?) {
        var amount = 0.0
        var dayPnl = 0.0
        var cost = 0.0
        var hasCost = false
        for holding in store.holdings {
            let percent = store.dayPercent(for: holding.code) ?? 0
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

    private func statBlock(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }

    // MARK: - 列表

    private var headerRow: some View {
        HStack {
            Text("基金").font(.caption2).foregroundStyle(.tertiary)
            Spacer()
            Text("今日").font(.caption2).foregroundStyle(.tertiary).frame(width: 52, alignment: .trailing)
            Text("持有金额").font(.caption2).foregroundStyle(.tertiary).frame(width: 64, alignment: .trailing)
            Text("当日盈亏").font(.caption2).foregroundStyle(.tertiary).frame(width: 64, alignment: .trailing)
            Text("持有收益").font(.caption2).foregroundStyle(.tertiary).frame(width: 78, alignment: .trailing)
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
    let onOpen: () -> Void

    var body: some View {
        let dayPnl = Holding.dayPnl(amount: holding.amount, dayPercent: dayPercent ?? 0)
        let totalPnl = Holding.totalPnl(amount: holding.amount, dayPercent: dayPercent ?? 0, cost: holding.cost)
        let totalPercent = Holding.totalPnlPercent(amount: holding.amount, dayPercent: dayPercent ?? 0, cost: holding.cost)

        return Button(action: onOpen) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(holding.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text("\(holding.code) · 点击查看走势")
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
                    .frame(width: 64, alignment: .trailing)
                Text(dayPnl.yuanText)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(CnStyle.color(for: dayPnl))
                    .frame(width: 64, alignment: .trailing)
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
                .frame(width: 78, alignment: .trailing)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .background(Color.primary.opacity(0.025))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
