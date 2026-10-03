import SwiftUI
import Charts

/// 基金详情:净值卡片、持仓盈亏卡片、可切换区间的净值走势图(Swift Charts)
struct FundDetailPage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let code: String
    var onBack: () -> Void
    var previewHolding: Holding? = nil
    var previewDetail: FundDetail? = nil
    var previewHistory: [NavPoint]? = nil

    @ObservedObject private var store = MarketStore.shared
    @State private var detail: FundDetail?
    @State private var history: [NavPoint] = []
    @State private var rangePoints = 30
    @State private var isLoading = true
    @State private var errorText: String?

    /// 时间档(近似交易日数量;蛋卷历史接口分页拉取)
    private static let ranges: [(String, Int)] = [
        ("近1月", 22),
        ("近3月", 66),
        ("近1年", 250),
        ("近5年", 1250),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                Text(detail?.name ?? code)
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
                Spacer()
                Text(code)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 280)
            } else if let errorText {
                VStack(spacing: 8) {
                    Text(errorText)
                        .font(.callout)
                        .foregroundStyle(.red)
                    Button("重试") { Task { await load() } }
                }
                .frame(maxWidth: .infinity, minHeight: 280)
            } else {
                if let detail {
                    heroHeader(detail)
                }
                statsSection
                stageReturnsSection
                rangePicker
                chartSection
            }
            Spacer()
        }
        .padding(14)
        .task {
            if let previewDetail, let previewHistory {
                detail = previewDetail
                history = previewHistory
                isLoading = false
            } else {
                await load()
            }
        }
    }

    private func load() async {
        isLoading = true
        errorText = nil
        do {
            async let detailTask = DanjuanAPI.shared.fetchFundDetail(code: code)
            async let historyTask = DanjuanAPI.shared.fetchNavHistory(code: code, maxPoints: 1300)
            let (fetchedDetail, fetchedHistory) = try await (detailTask, historyTask)
            detail = fetchedDetail
            history = fetchedHistory
            isLoading = false
        } catch {
            errorText = "加载失败:\(error.localizedDescription)"
            isLoading = false
        }
    }

    // MARK: - 净值与持仓统计

    private var holding: Holding? {
        previewHolding ?? store.holdings.first { $0.code == code }
    }

    /// Hero 区:大号净值 + 当日涨跌胶囊
    private func heroHeader(_ detail: FundDetail) -> some View {
        let color = CnStyle.color(for: detail.dayChangePercent)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(detail.unitNav.map { String(format: "%.4f", $0) } ?? "--")
                .font(.system(size: 26, weight: .heavy, design: .rounded).monospacedDigit())
                .contentTransition(reduceMotion ? .identity : .numericText())
            Text("净值 · \(detail.navDate ?? "--")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(detail.dayChangePercent?.percentText ?? "--")
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(reduceMotion ? .identity : .numericText())
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: [color.opacity(0.9), color.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                )
        }
        .padding(.bottom, 2)
    }

    private var statsSection: some View {
        // 详情里的净值涨跌仍按其净值日期展示；“当日盈亏”只使用当日有效行情。
        // 固定示例截图使用注入的预览数据，不读取本机账户的行情。
        let dayPercent: Double? = {
            if let previewDetail { return previewDetail.dayChangePercent }
            if let fromStore = store.effectivePercent(for: code)?.percent { return fromStore }
            guard let detail else { return nil }
            return FundQuotePolicy.effectivePercent(
                navDate: detail.navDate,
                navPercent: detail.dayChangePercent,
                estimateDate: nil,
                estimatePercent: nil,
                now: Date()
            )?.percent
        }()
        let dayPnl = holding.flatMap { holding in
            dayPercent.map { Holding.dayPnl(amount: holding.amount, dayPercent: $0) }
        }
        let totalPnl = holding.flatMap { holding in
            dayPercent.flatMap { Holding.totalPnl(amount: holding.amount, dayPercent: $0, cost: holding.cost) }
        }
        let totalPercent = holding.flatMap { holding in
            dayPercent.flatMap { Holding.totalPnlPercent(amount: holding.amount, dayPercent: $0, cost: holding.cost) }
        }

        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            statCard(
                title: "持有金额",
                value: holding.map(\.amount.yuanText) ?? "未添加持仓",
                color: holding == nil ? .secondary : .primary
            )
            statCard(title: "当日盈亏", value: dayPnl.map(\.yuanText) ?? "--", color: dayPnl.map { CnStyle.color(for: $0) } ?? .secondary)
            statCard(title: "持有收益", value: totalPnl.map(\.yuanText) ?? "--", color: totalPnl.map { CnStyle.color(for: $0) } ?? .secondary)
            statCard(title: "收益率", value: totalPercent?.percentText ?? "--", color: totalPercent.map { CnStyle.color(for: $0) } ?? .secondary)
        }
    }

    /// 阶段涨幅(近1月/3月/6月/1年),蛋卷有则展示
    private var stageReturnsSection: some View {
        let stages = detail?.stageReturns ?? []
        return Group {
            if !stages.isEmpty {
                HStack(spacing: 6) {
                    ForEach(stages) { stage in
                        VStack(spacing: 2) {
                            Text(stage.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(stage.percent.percentText)
                                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                                .foregroundStyle(CnStyle.color(for: stage.percent))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private func statCard(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    // MARK: - 走势图

    private var rangePicker: some View {
        Picker("", selection: $rangePoints) {
            ForEach(Self.ranges, id: \.1) { label, points in
                Text(label).tag(points)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var chartSection: some View {
        let points = Array(history.suffix(rangePoints))
        let minNav = points.map(\.nav).min() ?? 0
        let maxNav = points.map(\.nav).max() ?? 1
        let padding = max((maxNav - minNav) * 0.12, maxNav * 0.005)
        let lowerBound = max(0, minNav - padding)
        let periodPercent: Double? = {
            guard let first = points.first?.nav, let last = points.last?.nav, first != 0 else { return nil }
            return (last - first) / first * 100
        }()
        let lineColor = CnStyle.color(for: periodPercent)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("净值走势")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(periodPercent?.percentText ?? "--")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(lineColor)
            }
            if points.isEmpty {
                Text("暂无历史数据")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                Chart(points) { point in
                    LineMark(
                        x: .value("日期", point.dateValue ?? Date()),
                        y: .value("净值", point.nav)
                    )
                    .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(lineColor)

                    AreaMark(
                        x: .value("日期", point.dateValue ?? Date()),
                        yStart: .value("基线", lowerBound),
                        yEnd: .value("净值", point.nav)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [lineColor.opacity(0.22), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .chartYScale(domain: lowerBound...max(maxNav + padding, lowerBound + 0.0001))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4))
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4))
                }
                .frame(height: 245)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: rangePoints)
            }
        }
    }
}
