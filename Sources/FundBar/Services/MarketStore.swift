import Foundation

private struct FundFetchResult {
    let code: String
    let detail: FundDetail?
    let estimate: EastmoneyFundAPI.EstimateQuote?
}

private enum FundQuoteLoader {
    static func fetch(code: String) async -> FundFetchResult {
        let detail = try? await DanjuanAPI.shared.fetchFundDetail(code: code)
        return FundFetchResult(code: code, detail: detail, estimate: nil)
    }
}

private enum MarketRefreshEvent {
    case indices([IndexQuote], usedFallback: Bool, forcedMode: DataSourceMode?)
    case indexFailure(Error)
    case indexSkipped
    case sectors(gainers: [SectorQuote], losers: [SectorQuote])
    case sectorFailure(Error)
    case sectorDisabled
    case funds([FundFetchResult], estimateFailed: Bool)
}

/// 全局行情/持仓状态中心,由菜单栏面板与状态项图标共享。
@MainActor
final class MarketStore: ObservableObject {
    static let shared = MarketStore()

    @Published private(set) var indexQuotes: [IndexQuote] = []
    @Published private(set) var sectorGainers: [SectorQuote] = []
    @Published private(set) var sectorLosers: [SectorQuote] = []
    /// 持仓基金的最新净值信息,key 为基金代码
    @Published private(set) var fundQuotes: [String: FundDetail] = [:]
    /// 持仓基金的盘中估算涨跌幅(key 为基金代码;休市/无数据时为空)
    @Published private(set) var fundEstimates: [String: Double] = [:]
    /// 基金净值源最近一次成功拉取时间，与指数更新时间独立。
    @Published private(set) var fundLastUpdated: Date?
    /// 基金刷新结果，供页脚展示部分成功或失败。
    @Published private(set) var fundStatusText: String?
    /// 跨上海自然日时通知视图重新计算“今日盈亏”。
    @Published private(set) var valuationDay = TradingDay.string(Date())
    /// 指数迷你走势(secid -> 最近 20 日收盘价),腾讯日线,10 分钟缓存
    @Published private(set) var sparklines: [String: [Double]] = [:]
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isLoading = false
    /// 指数源错误；板块与基金各自独立刷新并报告状态。
    @Published private(set) var errorMessage: String?
    /// 降级提示:东财不可达已切换腾讯源(黄色状态)
    @Published private(set) var dataSourceNote: String?
    /// 板块榜单独失败(指数仍正常)
    @Published private(set) var sectorError: String?

    @Published var holdings: [Holding] = MarketStore.loadHoldings() {
        didSet { saveHoldings() }
    }

    private var timer: Timer?
    private var dayRolloverTimer: Timer?
    private var hasLoadedOnce = false
    private var sparklinesLoadedAt: Date?
    private var isLoadingSparklines = false
    private var consecutiveFailures = 0
    private var nextAllowedRefresh = Date.distantPast
    private var isRefreshing = false
    private var refreshGeneration: UInt64 = 0
    private var eastMoneyConsecutiveFailures = 0
    private var eastMoneyLastFailureAt: Date?
    private var fundEstimateQuotes: [String: EastmoneyFundAPI.EstimateQuote] = [:]

    private init() {
        startTimer()
        scheduleDayRollover()
    }

    var refreshInterval: TimeInterval {
        // 从未设置过 → 默认 60 秒;显式设为 0 表示仅手动刷新
        if UserDefaults.standard.object(forKey: SettingsKey.refreshInterval) == nil {
            return 60
        }
        return UserDefaults.standard.double(forKey: SettingsKey.refreshInterval)
    }

    /// 用户在设置中选择的数据源模式
    var dataSourceMode: DataSourceMode {
        DataSourceMode(rawValue: UserDefaults.standard.string(forKey: SettingsKey.dataSource) ?? "") ?? .auto
    }

    /// 设置页切换数据源后调用,立即按新模式刷新
    func applyDataSourceSetting() {
        nextAllowedRefresh = .distantPast
        Task { await refresh(showLoading: false) }
    }

    /// 休市提示:行情数据日期早于今天时返回提示文案
    var marketClosedNotice: String? {
        guard let date = indexQuotes.compactMap(\.dataDate).first else { return nil }
        let today = TradingDay.string(Date())
        guard date != today, let tradingDay = TradingDay.date(from: date) else { return nil }
        return "今日休市,展示 \(TradingDay.string(tradingDay).dropFirst(5))(\(TradingDay.weekdayLabel(tradingDay)))收盘行情"
    }

    /// 设置页修改刷新间隔后调用,重建定时器;间隔为 0(仅手动)时不创建定时器
    func startTimer() {
        timer?.invalidate()
        timer = nil
        guard RefreshPolicy.isScheduled(interval: refreshInterval) else { return }
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { _ in
            Task { @MainActor in
                MarketStore.shared.rolloverFundDayIfNeeded()
                guard RefreshPolicy.autoRefreshAllowed(isWeekend: TradingDay.isWeekend()) else { return }
                await MarketStore.shared.refresh(showLoading: false)
            }
        }
    }

    private func scheduleDayRollover() {
        dayRolloverTimer?.invalidate()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        guard let nextMidnight = calendar.nextDate(
            after: Date(),
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) else { return }
        let timer = Timer(fire: nextMidnight, interval: 0, repeats: false) { _ in
            Task { @MainActor in
                MarketStore.shared.rolloverFundDayIfNeeded()
                MarketStore.shared.scheduleDayRollover()
            }
        }
        dayRolloverTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func rolloverFundDayIfNeeded() {
        let today = TradingDay.string(Date())
        guard valuationDay != today else { return }
        valuationDay = today
        fundEstimateQuotes = fundEstimateQuotes.filter { $0.value.dataDate == today }
        fundEstimates = fundEstimateQuotes.mapValues(\.percent)
    }

    /// 面板打开时加载一次;仅手动模式下数据超过 60 秒也会补一次
    func refreshIfNeeded() async {
        rolloverFundDayIfNeeded()
        if hasLoadedOnce {
            guard refreshInterval <= 0 else { return }
            if let last = lastUpdated, Date().timeIntervalSince(last) < 60 { return }
            await refresh(showLoading: false)
            return
        }
        await refresh(showLoading: true)
    }

    func refresh(showLoading: Bool) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshGeneration &+= 1
        let generation = refreshGeneration
        rolloverFundDayIfNeeded()
        if showLoading { isLoading = true }
        // 看门狗解除极端挂起；generation 阻止旧请求随后覆盖新一轮结果。
        let watchdog = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 90_000_000_000) }
            catch { return }
            guard refreshGeneration == generation else { return }
            refreshGeneration &+= 1
            isRefreshing = false
            if showLoading { isLoading = false }
        }
        defer {
            watchdog.cancel()
            if refreshGeneration == generation {
                isRefreshing = false
                if showLoading { isLoading = false }
            }
        }

        // 三组数据同时刷新，各自完成时立即更新。指数退避只跳过指数，不拖住基金。
        let shouldFetchIndices = showLoading || Date() >= nextAllowedRefresh
        let codes = Array(Set(holdings.map(\.code))).sorted()
        var indicesUpdated = false
        await withTaskGroup(of: MarketRefreshEvent.self) { group in
            group.addTask { await self.fetchIndexEvent(shouldFetch: shouldFetchIndices) }
            group.addTask { await self.fetchSectorEvent() }
            group.addTask { await self.fetchFundEvent(codes: codes) }
            for await event in group {
                guard refreshGeneration == generation else {
                    group.cancelAll()
                    break
                }
                switch event {
                case let .indices(quotes, usedFallback, forcedMode):
                    indexQuotes = quotes
                    lastUpdated = Date()
                    errorMessage = nil
                    consecutiveFailures = 0
                    nextAllowedRefresh = .distantPast
                    indicesUpdated = true
                    switch forcedMode ?? .auto {
                    case .tencent:
                        dataSourceNote = "使用腾讯源(日经/KOSPI 暂缺)"
                    case .eastmoney, .auto:
                        dataSourceNote = usedFallback ? "东财行情不可达,已切换腾讯备用源(日经/KOSPI 暂缺)" : nil
                    }
                case let .indexFailure(error):
                    consecutiveFailures += 1
                    nextAllowedRefresh = RefreshPolicy.nextAllowedAt(
                        lastInterval: max(refreshInterval, 30),
                        consecutiveFailures: consecutiveFailures,
                        from: Date()
                    )
                    dataSourceNote = nil
                    errorMessage = "指数获取失败:\(friendlyNetworkMessage(error))"
                case .indexSkipped:
                    break
                case let .sectors(gainers, losers):
                    sectorGainers = gainers
                    sectorLosers = losers
                    sectorError = nil
                case let .sectorFailure(error):
                    sectorGainers = []
                    sectorLosers = []
                    sectorError = "板块榜暂不可用:\(friendlyNetworkMessage(error))"
                case .sectorDisabled:
                    sectorGainers = []
                    sectorLosers = []
                    sectorError = "板块榜仅东财源提供,当前数据源为腾讯"
                case let .funds(results, estimateFailed):
                    applyFundResults(results, total: codes.count, estimateFailed: estimateFailed)
                    checkAlerts()
                }
            }
        }
        guard refreshGeneration == generation else { return }
        hasLoadedOnce = true
        if indicesUpdated {
            await loadSparklinesIfNeeded(generation: generation)
        }
    }

    private func fetchIndexEvent(shouldFetch: Bool) async -> MarketRefreshEvent {
        guard shouldFetch else { return .indexSkipped }
        do {
            let result = try await fetchIndicesWithFallback()
            return .indices(result.quotes, usedFallback: result.usedFallback, forcedMode: result.forcedMode)
        } catch {
            return .indexFailure(error)
        }
    }

    private func fetchSectorEvent() async -> MarketRefreshEvent {
        guard dataSourceMode != .tencent else { return .sectorDisabled }
        do {
            async let gainers = EastmoneyAPI.shared.fetchSectorRank(ascending: false, count: 8)
            async let losers = EastmoneyAPI.shared.fetchSectorRank(ascending: true, count: 8)
            return .sectors(gainers: try await gainers, losers: try await losers)
        } catch {
            return .sectorFailure(error)
        }
    }

    private func fetchFundEvent(codes: [String]) async -> MarketRefreshEvent {
        guard !codes.isEmpty, !Task.isCancelled else { return .funds([], estimateFailed: false) }
        async let estimatesTask = EastmoneyFundAPI.shared.fetchEstimateBatches(codes: codes)
        var results: [FundFetchResult] = []
        var remaining = codes.makeIterator()
        await withTaskGroup(of: FundFetchResult.self) { group in
            // 净值同时最多请求 4 只；估值由独立批量请求并行获取。
            for _ in 0..<min(4, codes.count) {
                if let code = remaining.next() {
                    group.addTask { await FundQuoteLoader.fetch(code: code) }
                }
            }
            for await result in group {
                results.append(result)
                if !Task.isCancelled, let code = remaining.next() {
                    group.addTask { await FundQuoteLoader.fetch(code: code) }
                }
            }
        }
        let estimates = await estimatesTask
        let combined = results.map {
            FundFetchResult(code: $0.code, detail: $0.detail, estimate: estimates.quotes[$0.code])
        }
        return .funds(combined, estimateFailed: estimates.failedBatchCount > 0)
    }

    /// 数据源状态明细(页脚悬停提示)
    var sourceDetailText: String {
        var parts: [String] = []
        if errorMessage != nil {
            parts.append("指数:不可用")
        } else if dataSourceMode == .tencent || dataSourceNote != nil {
            parts.append("指数:腾讯源")
        } else {
            parts.append("指数:东财")
        }
        if indexQuotes.contains(where: { $0.def.secid == "100.N225" && $0.price == nil }) {
            parts.append("日经/KOSPI:暂缺")
        }
        if dataSourceMode == .tencent || sectorError != nil {
            parts.append("板块:不可用")
        } else {
            parts.append("板块:东财")
        }
        parts.append(fundStatusText ?? "基金:蛋卷")
        if let fundLastUpdated {
            parts.append("基金更新:\(fundLastUpdated.formatted(.dateTime.hour().minute()))")
        }
        return parts.joined(separator: " · ")
    }

    /// 迷你走势 10 分钟缓存,过期后从腾讯日线接口并发拉取
    private func loadSparklinesIfNeeded(generation: UInt64) async {
        guard !isLoadingSparklines else { return }
        if let loaded = sparklinesLoadedAt, Date().timeIntervalSince(loaded) < 600 { return }
        isLoadingSparklines = true
        defer { isLoadingSparklines = false }
        var result: [String: [Double]] = [:]
        await withTaskGroup(of: (String, [Double])?.self) { group in
            for def in IndexDef.all {
                guard let code = def.tencentCode else { continue }
                group.addTask {
                    guard let closes = try? await TencentAPI.shared.fetchDailyCloses(code: code), !closes.isEmpty else {
                        return nil
                    }
                    return (def.secid, closes)
                }
            }
            for await pair in group {
                if let pair { result[pair.0] = pair.1 }
            }
        }
        if !result.isEmpty, refreshGeneration == generation {
            sparklines = result
            sparklinesLoadedAt = Date()
        }
    }

    /// 指数获取:按设置选择数据源;auto 模式下东财失败自动切腾讯
    private func fetchIndicesWithFallback() async throws -> (quotes: [IndexQuote], usedFallback: Bool, forcedMode: DataSourceMode?) {
        switch dataSourceMode {
        case .eastmoney:
            return (try await fetchIndicesFromEastmoney(), false, .eastmoney)
        case .tencent:
            return (try await fetchIndicesFromTencent(), true, .tencent)
        case .auto:
            // 东财熔断:连续失败冷却期内直接走腾讯,避免每次刷新都白等它超时
            if RefreshPolicy.eastMoneyInCooldown(
                consecutiveFailures: eastMoneyConsecutiveFailures,
                lastFailureAt: eastMoneyLastFailureAt
            ) {
                do {
                    return (try await fetchIndicesFromTencent(), true, .tencent)
                } catch {
                    return (try await fetchIndicesFromEastmoney(), false, .eastmoney)
                }
            }
            do {
                let quotes = try await fetchIndicesFromEastmoney()
                eastMoneyConsecutiveFailures = 0
                return (quotes, false, nil)
            } catch {
                eastMoneyConsecutiveFailures += 1
                eastMoneyLastFailureAt = Date()
                return (try await fetchIndicesFromTencent(), true, nil)
            }
        }
    }

    private func fetchIndicesFromEastmoney() async throws -> [IndexQuote] {
        let defs = IndexDef.all
        let quotes = try await EastmoneyAPI.shared.fetchQuotes(secids: defs.map(\.secid))
        let fallbackDate = TradingDay.string(TradingDay.mostRecent())
        return defs.map { def in
            let quote = quotes[def.codePart] ?? quotes[def.name]
            return IndexQuote(
                def: def,
                price: quote?.price,
                change: quote?.change,
                changePercent: quote?.changePercent,
                dataDate: fallbackDate
            )
        }
    }

    private func fetchIndicesFromTencent() async throws -> [IndexQuote] {
        let defs = IndexDef.all
        let supported = defs.filter { $0.tencentCode != nil }
        let tencentQuotes = try await TencentAPI.shared.fetchQuotes(codes: supported.compactMap(\.tencentCode))
        let fallbackDate = TradingDay.string(TradingDay.mostRecent())
        return defs.map { def in
            guard let code = def.tencentCode, let quote = tencentQuotes[code] else {
                // 腾讯源不支持(日经225/韩国KOSPI),置空由 UI 显示"暂不可用"
                return IndexQuote(def: def, price: nil, change: nil, changePercent: nil, dataDate: nil)
            }
            return IndexQuote(
                def: def,
                price: quote.price,
                change: quote.change,
                changePercent: quote.changePercent,
                dataDate: quote.dataDate ?? fallbackDate
            )
        }
    }

    /// 某只基金可用于“今日”统计的涨跌幅。
    func dayPercent(for code: String) -> Double? {
        effectivePercent(for: code)?.percent
    }

    /// 展示、盈亏、提醒共用口径：仅接受有上海当日日期的源数据。
    func effectivePercent(for code: String) -> (percent: Double, isEstimate: Bool)? {
        let detail = fundQuotes[code]
        let estimate = fundEstimateQuotes[code]
        guard let result = FundQuotePolicy.effectivePercent(
            navDate: detail?.navDate,
            navPercent: detail?.dayChangePercent,
            estimateDate: estimate?.dataDate,
            estimatePercent: estimate?.percent
        ) else { return nil }
        return (result.percent, result.isEstimate)
    }

    func fundDetail(for code: String) -> FundDetail? {
        fundQuotes[code]
    }

    private func applyFundResults(_ results: [FundFetchResult], total: Int, estimateFailed: Bool) {
        var updated = fundQuotes
        var estimates: [String: EastmoneyFundAPI.EstimateQuote] = [:]
        let today = TradingDay.string(Date())
        var updatedCount = 0
        for result in results {
            if let detail = result.detail {
                updated[result.code] = detail
                updatedCount += 1
            }
            if let estimate = result.estimate, estimate.dataDate == today {
                estimates[result.code] = estimate
            }
        }
        fundQuotes = updated
        // 每次重新构建估值快照；接口失败后不能沿用上次盘中的估值。
        fundEstimateQuotes = estimates
        fundEstimates = estimates.mapValues(\.percent)
        if updatedCount > 0 { fundLastUpdated = Date() }
        let usableToday = results.filter { effectivePercent(for: $0.code) != nil }.count
        if total == 0 {
            fundStatusText = nil
        } else if updatedCount == total {
            fundStatusText = "基金已更新 \(updatedCount)/\(total),今日涨跌可用 \(usableToday)/\(total)"
        } else if updatedCount > 0 {
            fundStatusText = "基金已更新 \(updatedCount)/\(total),今日涨跌可用 \(usableToday)/\(total)"
        } else {
            fundStatusText = "基金净值获取失败,今日涨跌可用 \(usableToday)/\(total)"
        }
        if estimateFailed, total > 0 {
            fundStatusText = (fundStatusText ?? "基金") + " · 盘中估值请求有失败"
        }
    }

    // MARK: - 涨跌提醒

    /// 每次行情刷新后检查持仓是否越过提醒阈值,发系统通知;每只基金每天最多一次
    private func checkAlerts() {
        guard UserDefaults.standard.bool(forKey: SettingsKey.alertEnabled) else { return }
        var threshold = UserDefaults.standard.double(forKey: SettingsKey.alertThreshold)
        if threshold <= 0 { threshold = 2.0 }
        let today = NotificationManager.todayString()
        var notified = Set(UserDefaults.standard.stringArray(forKey: SettingsKey.alertNotified) ?? [])
        var percents: [String: Double] = [:]
        for holding in holdings {
            percents[holding.code] = effectivePercent(for: holding.code)?.percent
        }
        let found = FundAlert.candidates(
            holdings: holdings,
            percents: percents,
            threshold: threshold,
            notifiedKeys: notified,
            today: today
        )
        guard !found.isEmpty else { return }
        for candidate in found {
            NotificationManager.shared.sendFundAlert(candidate, date: today)
            notified.insert(FundAlert.notifiedKey(code: candidate.code, date: today))
        }
        // 只保留今天的记录,防止列表无限增长
        let pruned = Array(notified).filter { $0.hasPrefix("fundbar.alert.\(today).") }
        UserDefaults.standard.set(pruned, forKey: SettingsKey.alertNotified)
    }

    // MARK: - 持仓管理

    func addOrUpdateHolding(_ holding: Holding) {
        if let index = holdings.firstIndex(where: { $0.code == holding.code }) {
            holdings[index] = holding
        } else {
            holdings.append(holding)
        }
    }

    func removeHolding(code: String) {
        holdings.removeAll { $0.code == code }
        fundQuotes[code] = nil
        fundEstimates[code] = nil
        fundEstimateQuotes[code] = nil
    }

    /// iCloud 同步整包应用(远端覆盖本地)
    func replaceHoldings(_ newHoldings: [Holding]) {
        holdings = newHoldings
    }

    private func saveHoldings() {
        guard let data = try? JSONEncoder().encode(holdings) else { return }
        UserDefaults.standard.set(data, forKey: SettingsKey.holdings)
    }

    private static func loadHoldings() -> [Holding] {
        guard let data = UserDefaults.standard.data(forKey: SettingsKey.holdings) else { return [] }
        return (try? JSONDecoder().decode([Holding].self, from: data)) ?? []
    }
}
