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
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    @Published var holdings: [Holding] = MarketStore.loadHoldings() {
        didSet { saveHoldings() }
    }

    private var timer: Timer?
    private var hasLoadedOnce = false

    private init() {
        startTimer()
    }

    var refreshInterval: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: SettingsKey.refreshInterval)
        return stored > 0 ? stored : 60
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
        do {
            async let indicesTask = fetchIndices()
            async let gainersTask = EastmoneyAPI.shared.fetchSectorRank(ascending: false, count: 8)
            async let losersTask = EastmoneyAPI.shared.fetchSectorRank(ascending: true, count: 8)
            let (indices, gainers, losers) = try await (indicesTask, gainersTask, losersTask)
            indexQuotes = indices
            sectorGainers = gainers
            sectorLosers = losers
            lastUpdated = Date()
            errorMessage = nil
            hasLoadedOnce = true
            await refreshFundQuotes()
        } catch {
            errorMessage = "行情获取失败:\(error.localizedDescription)"
        }
    }

    /// 某只基金的当日涨跌幅(用于持仓盈亏计算)
    func dayPercent(for code: String) -> Double? {
        fundQuotes[code]?.dayChangePercent
    }

    func fundDetail(for code: String) -> FundDetail? {
        fundQuotes[code]
    }

    private func fetchIndices() async throws -> [IndexQuote] {
        let defs = IndexDef.all
        let quotes = try await EastmoneyAPI.shared.fetchQuotes(secids: defs.map(\.secid))
        return defs.map { def in
            let quote = quotes[def.codePart] ?? quotes[def.name]
            return IndexQuote(
                def: def,
                price: quote?.price,
                change: quote?.change,
                changePercent: quote?.changePercent
            )
        }
    }

    /// 拉取所有持仓基金的当日净值与涨跌幅
    private func refreshFundQuotes() async {
        var updated = fundQuotes
        for holding in holdings {
            guard let detail = try? await DanjuanAPI.shared.fetchFundDetail(code: holding.code) else { continue }
            updated[holding.code] = detail
        }
        fundQuotes = updated
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
