import Foundation

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
    /// 指数迷你走势(secid -> 最近 20 日收盘价),腾讯日线,10 分钟缓存
    @Published private(set) var sparklines: [String: [Double]] = [:]
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isLoading = false
    /// 致命错误:所有数据源都失败
    @Published private(set) var errorMessage: String?
    /// 降级提示:东财不可达已切换腾讯源(黄色状态)
    @Published private(set) var dataSourceNote: String?
    /// 板块榜单独失败(指数仍正常)
    @Published private(set) var sectorError: String?

    @Published var holdings: [Holding] = MarketStore.loadHoldings() {
        didSet { saveHoldings() }
    }

    private var timer: Timer?
    private var hasLoadedOnce = false
    private var sparklinesLoadedAt: Date?
    private var isLoadingSparklines = false

    private init() {
        startTimer()
    }

    var refreshInterval: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: SettingsKey.refreshInterval)
        return stored > 0 ? stored : 60
    }

    /// 用户在设置中选择的数据源模式
    var dataSourceMode: DataSourceMode {
        DataSourceMode(rawValue: UserDefaults.standard.string(forKey: SettingsKey.dataSource) ?? "") ?? .auto
    }

    /// 设置页切换数据源后调用,立即按新模式刷新
    func applyDataSourceSetting() {
        Task { await refresh(showLoading: false) }
    }

    /// 休市提示:行情数据日期早于今天时返回提示文案
    var marketClosedNotice: String? {
        guard let date = indexQuotes.compactMap(\.dataDate).first else { return nil }
        let today = TradingDay.string(Date())
        guard date != today, let tradingDay = TradingDay.date(from: date) else { return nil }
        return "今日休市,展示 \(TradingDay.string(tradingDay).dropFirst(5))(\(TradingDay.weekdayLabel(tradingDay)))收盘行情"
    }

    /// 设置页修改刷新间隔后调用,重建定时器
    func startTimer() {
        timer?.invalidate()
        let interval = refreshInterval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in
                await MarketStore.shared.refresh(showLoading: false)
            }
        }
    }

    /// 面板首次打开时加载一次
    func refreshIfNeeded() async {
        guard !hasLoadedOnce else { return }
        await refresh(showLoading: true)
    }

    func refresh(showLoading: Bool) async {
        if showLoading { isLoading = true }
        defer { if showLoading { isLoading = false } }

        // 指数:按数据源设置获取(auto 模式东财 -> 腾讯 降级链)
        var indices: [IndexQuote]?
        do {
            let result = try await fetchIndicesWithFallback()
            indices = result.quotes
            switch result.forcedMode ?? .auto {
            case .tencent:
                dataSourceNote = "使用腾讯源(日经/KOSPI 暂缺)"
            case .eastmoney, .auto:
                dataSourceNote = result.usedFallback ? "东财行情不可达,已切换腾讯备用源(日经/KOSPI 暂缺)" : nil
            }
        } catch {
            dataSourceNote = nil
            errorMessage = "行情获取失败:\(friendlyNetworkMessage(error))"
        }

        // 板块榜:仅东财提供,失败/腾讯模式不阻塞指数展示
        if dataSourceMode == .tencent {
            sectorGainers = []
            sectorLosers = []
            sectorError = "板块榜仅东财源提供,当前数据源为腾讯"
        } else {
            do {
                async let gainersTask = EastmoneyAPI.shared.fetchSectorRank(ascending: false, count: 8)
                async let losersTask = EastmoneyAPI.shared.fetchSectorRank(ascending: true, count: 8)
                let (gainers, losers) = try await (gainersTask, losersTask)
                sectorGainers = gainers
                sectorLosers = losers
                sectorError = dataSourceNote == nil ? nil : "板块榜由东财源提供,当前处于腾讯降级源"
            } catch {
                sectorGainers = []
                sectorLosers = []
                sectorError = dataSourceNote == nil ? "板块榜暂不可用:\(friendlyNetworkMessage(error))" : nil
            }
        }

        if let indices {
            indexQuotes = indices
            lastUpdated = Date()
            errorMessage = nil
            hasLoadedOnce = true
            await refreshFundQuotes()
            checkAlerts()
            await loadSparklinesIfNeeded()
        }
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
        parts.append("基金:蛋卷")
        return parts.joined(separator: " · ")
    }

    /// 迷你走势 10 分钟缓存,过期后从腾讯日线接口并发拉取
    private func loadSparklinesIfNeeded() async {
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
        if !result.isEmpty {
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
            do {
                return (try await fetchIndicesFromEastmoney(), false, nil)
            } catch {
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

    /// 某只基金的当日涨跌幅(净值口径)
    func dayPercent(for code: String) -> Double? {
        fundQuotes[code]?.dayChangePercent
    }

    /// 展示与盈亏计算口径:盘中优先用估算值,闭市回落到净值涨跌
    func effectivePercent(for code: String) -> (percent: Double, isEstimate: Bool)? {
        if let estimate = fundEstimates[code] {
            return (estimate, true)
        }
        if let navPercent = fundQuotes[code]?.dayChangePercent {
            return (navPercent, false)
        }
        return nil
    }

    func fundDetail(for code: String) -> FundDetail? {
        fundQuotes[code]
    }

    /// 拉取所有持仓基金的当日净值(蛋卷)与盘中估值(东财)
    private func refreshFundQuotes() async {
        var updated = fundQuotes
        var updatedEstimates = fundEstimates
        for holding in holdings {
            if let detail = try? await DanjuanAPI.shared.fetchFundDetail(code: holding.code) {
                updated[holding.code] = detail
            }
            // 休市时接口返回空,置 nil 回落净值口径
            updatedEstimates[holding.code] = try? await EastmoneyFundAPI.shared.fetchEstimate(code: holding.code)
        }
        fundQuotes = updated
        fundEstimates = updatedEstimates
    }

    // MARK: - 涨跌提醒

    /// 每次行情刷新后检查持仓是否越过提醒阈值,发系统通知;每只基金每天最多一次
    private func checkAlerts() {
        guard UserDefaults.standard.bool(forKey: SettingsKey.alertEnabled) else { return }
        var threshold = UserDefaults.standard.double(forKey: SettingsKey.alertThreshold)
        if threshold <= 0 { threshold = 2.0 }
        let today = NotificationManager.todayString()
        var notified = Set(UserDefaults.standard.stringArray(forKey: SettingsKey.alertNotified) ?? [])
        let found = FundAlert.candidates(
            holdings: holdings,
            quotes: fundQuotes,
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
