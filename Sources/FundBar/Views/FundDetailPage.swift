import SwiftUI
import Charts

/// 基金详情:净值卡片、持仓盈亏卡片、可切换区间的净值走势图(Swift Charts)
struct FundDetailPage: View {
    let code: String
    var onBack: () -> Void

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
        .task { await load() }
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
        store.holdings.first { $0.code == code }
    }

    /// Hero 区:大号净值 + 当日涨跌胶囊
    private func heroHeader(_ detail: FundDetail) -> some View {
        let color = CnStyle.color(for: detail.dayChangePercent)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(detail.unitNav.map { String(format: "%.4f", $0) } ?? "--")
                .font(.system(size: 26, weight: .heavy, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
            Text("净值 · \(detail.navDate ?? "--")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(detail.dayChangePercent?.percentText ?? "--")
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
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
        let dayPercent = detail?.dayChangePercent
        let dayPnl = holding.map { Holding.dayPnl(amount: $0.amount, dayPercent: dayPercent ?? 0) }
        let totalPnl = holding.flatMap {
            Holding.totalPnl(amount: $0.amount, dayPercent: dayPercent ?? 0, cost: $0.cost)
        }
        let totalPercent = holding.flatMap {
            Holding.totalPnlPercent(amount: $0.amount, dayPercent: dayPercent ?? 0, cost: $0.cost)
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
                        y: .value("净值", point.nav)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [lineColor.opacity(0.22), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4))
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4))
                }
                .frame(height: 185)
            }
        }
    }
}
