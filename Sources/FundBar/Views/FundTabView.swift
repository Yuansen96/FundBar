import SwiftUI

enum HoldingSortOrder: String, CaseIterable {
    case original
    case dayPercent
    case dayPnl
    case amount
    case totalPnl

    var title: String {
        switch self {
        case .original: return "默认顺序"
        case .dayPercent: return "今日涨跌"
        case .dayPnl: return "当日盈亏"
        case .amount: return "持有金额"
        case .totalPnl: return "持有收益"
        }
    }
}

/// 缺少排序数值时置底；数值相同则沿用持仓的保存顺序。
enum HoldingSorting {
    static func sorted(
        _ holdings: [Holding],
        by order: HoldingSortOrder,
        percents: [String: Double]
    ) -> [Holding] {
        guard order != .original else { return holdings }

        let ranked: [(index: Int, holding: Holding, value: Double?)] = holdings.enumerated().map { index, holding in
            let percent = percents[holding.code].flatMap { $0.isFinite ? $0 : nil }
            let value: Double?
            switch order {
            case .original:
                value = nil
            case .dayPercent:
                value = percent
            case .dayPnl:
                value = percent.flatMap { holding.amount.isFinite ? Holding.dayPnl(amount: holding.amount, dayPercent: $0) : nil }
            case .amount:
                value = holding.amount.isFinite ? holding.amount : nil
            case .totalPnl:
                value = percent.flatMap {
                    holding.amount.isFinite ? Holding.totalPnl(amount: holding.amount, dayPercent: $0, cost: holding.cost) : nil
                }
            }
            return (index, holding, value.flatMap { $0.isFinite ? $0 : nil })
        }

        return ranked.sorted { left, right in
            switch (left.value, right.value) {
            case let (.some(lhs), .some(rhs)) where lhs != rhs:
                return lhs > rhs
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                return left.index < right.index
            }
        }.map { $0.holding }
    }
}

/// 我的基金页签:渐变盈亏横幅 + 持仓列表;行支持编辑/删除,点击查看走势
struct FundTabView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var store = MarketStore.shared
    @State private var sortOrder: HoldingSortOrder = .original
    let onAdd: () -> Void
    let onEdit: (Holding) -> Void
    let onOpenDetail: (String) -> Void
    var previewHoldings: [Holding]? = nil
    var previewPercents: [String: Double]? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 5) {
                if holdings.isEmpty {
                    emptyState
                } else {
                    summaryBanner
                    listToolbar
                    headerRow
                    ForEach(sortedHoldings) { holding in
                        let percentInfo = percentInfo(for: holding.code)
                        FundRow(
                            holding: holding,
                            dayPercent: percentInfo?.percent,
                            isEstimate: percentInfo?.isEstimate ?? false,
                            onOpen: { onOpenDetail(holding.code) },
                            onEdit: { onEdit(holding) }
                        )
                        .contextMenu {
                            Button("编辑持有金额") { onEdit(holding) }
                            if previewHoldings == nil {
                                Divider()
                                Button("删除", role: .destructive) {
                                    store.removeHolding(code: holding.code)
                                }
                            }
                        }
                    }
                }
                Button(action: onAdd) {
                    Label(holdings.isEmpty ? "添加基金(代码 + 持有金额)" : "添加基金", systemImage: "plus")
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

    private var holdings: [Holding] { previewHoldings ?? store.holdings }

    private func percentInfo(for code: String) -> (percent: Double, isEstimate: Bool)? {
        if previewHoldings != nil {
            return previewPercents?[code].map { (percent: $0, isEstimate: false) }
        }
        return store.effectivePercent(for: code)
    }

    private var displayPercents: [String: Double] {
        var percents: [String: Double] = [:]
        for holding in holdings {
            percents[holding.code] = percentInfo(for: holding.code)?.percent
        }
        return percents
    }

    private var sortedHoldings: [Holding] {
        HoldingSorting.sorted(holdings, by: sortOrder, percents: displayPercents)
    }

    // MARK: - 盈亏汇总横幅

    private var summaryTotals: PortfolioSummary {
        PortfolioSummary(holdings: holdings, percents: displayPercents)
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
                Text(totals.dayPnl?.yuanText ?? "--")
                    .font(.system(size: 26, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(dayColor)
                    .contentTransition(reduceMotion ? .identity : .numericText())
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
            if totals.missingQuoteCount > 0 || totals.missingCostCount > 0 {
                Text(summaryNote(totals))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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

    private func summaryNote(_ totals: PortfolioSummary) -> String {
        var notes: [String] = []
        if totals.missingQuoteCount > 0 { notes.append("\(totals.missingQuoteCount) 只基金今日有效行情待更新") }
        if totals.missingCostCount > 0 { notes.append("\(totals.missingCostCount) 只基金未填成本，持有收益待补全") }
        return notes.joined(separator: " · ")
    }

    // MARK: - 列表

    private var listToolbar: some View {
        HStack(spacing: 6) {
            Text("持仓")
                .font(.caption.weight(.semibold))
            Text("\(holdings.count) 只")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                ForEach(HoldingSortOrder.allCases, id: \.self) { option in
                    Button {
                        sortOrder = option
                    } label: {
                        if option == sortOrder {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                Label("排序 · \(sortOrder.title)", systemImage: "arrow.up.arrow.down")
                    .font(.caption)
            }
            .fixedSize()
            .help("从高到低排序；缺少行情或成本的基金排在末尾")
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 2)
    }

    private var headerRow: some View {
        HStack {
            Text("基金").font(.caption2).foregroundStyle(.tertiary)
            Spacer()
            Text("今日").font(.caption2).foregroundStyle(.tertiary).frame(width: 52, alignment: .trailing)
            Text("持有金额").font(.caption2).foregroundStyle(.tertiary).frame(width: 62, alignment: .trailing)
            Text("当日盈亏").font(.caption2).foregroundStyle(.tertiary).frame(width: 62, alignment: .trailing)
            Text("持有收益").font(.caption2).foregroundStyle(.tertiary).frame(width: 76, alignment: .trailing)
            Text("编辑").font(.caption2).foregroundStyle(.tertiary).frame(width: 28, alignment: .center)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let holding: Holding
    let dayPercent: Double?
    var isEstimate = false
    let onOpen: () -> Void
    let onEdit: () -> Void
    @State private var hovered = false

    var body: some View {
        let dayPnl = dayPercent.map { Holding.dayPnl(amount: holding.amount, dayPercent: $0) }
        let totalPnl = dayPercent.flatMap { Holding.totalPnl(amount: holding.amount, dayPercent: $0, cost: holding.cost) }
        let totalPercent = dayPercent.flatMap { Holding.totalPnlPercent(amount: holding.amount, dayPercent: $0, cost: holding.cost) }

        return HStack(spacing: 4) {
            Button(action: onOpen) {
                HStack {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(CnStyle.color(for: dayPercent).opacity(0.75))
                        .frame(width: 3, height: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(holding.name)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(2)
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
                        Text(holding.code)
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
                    Text(dayPnl?.yuanText ?? "--")
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
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("查看 \(holding.name) 的走势")
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28, height: 28)
                    .background(Color.accentColor.opacity(hovered ? 0.14 : 0.08), in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("编辑 \(holding.name) 的持仓")
            .accessibilityLabel("编辑 \(holding.name) 的持仓")
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.primary.opacity(hovered ? 0.07 : 0.03))
        )
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
    }
}
