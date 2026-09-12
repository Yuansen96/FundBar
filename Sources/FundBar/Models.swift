import Foundation

// MARK: - 指数定义

enum IndexRegion: String, CaseIterable, Identifiable {
    case cn = "A股"
    case asia = "亚太"
    case us = "美股"

    var id: String { rawValue }
}

struct IndexDef: Identifiable, Hashable {
    let name: String
    /// 菜单栏摘要用的短名
    let shortName: String
    /// 东方财富 secid,如 "1.000001"
    let secid: String
    /// 腾讯行情源代码,如 "sh000001";nil 表示腾讯源不支持该指数
    let tencentCode: String?
    let region: IndexRegion

    var id: String { secid }
    var codePart: String { secid.split(separator: ".").last.map(String.init) ?? secid }
}

extension IndexDef {
    /// 全部可订阅指数(东财 secid 为主源,腾讯代码为降级源;均已实测)
    static let all: [IndexDef] = [
        IndexDef(name: "上证指数", shortName: "上证", secid: "1.000001", tencentCode: "sh000001", region: .cn),
        IndexDef(name: "深证成指", shortName: "深成", secid: "0.399001", tencentCode: "sz399001", region: .cn),
        IndexDef(name: "创业板指", shortName: "创业板", secid: "0.399006", tencentCode: "sz399006", region: .cn),
        IndexDef(name: "恒生指数", shortName: "恒生", secid: "100.HSI", tencentCode: "hkHSI", region: .asia),
        IndexDef(name: "日经225", shortName: "日经", secid: "100.N225", tencentCode: nil, region: .asia),
        IndexDef(name: "韩国KOSPI", shortName: "KOSPI", secid: "100.KS11", tencentCode: nil, region: .asia),
        IndexDef(name: "道琼斯", shortName: "道指", secid: "100.DJIA", tencentCode: "usDJI", region: .us),
        IndexDef(name: "纳斯达克", shortName: "纳指", secid: "100.NDX", tencentCode: "usIXIC", region: .us),
        IndexDef(name: "标普500", shortName: "标普", secid: "100.SPX", tencentCode: "usINX", region: .us),
    ]
}

// MARK: - 行情模型

struct IndexQuote: Identifiable {
    let def: IndexDef
    let price: Double?
    let change: Double?
    let changePercent: Double?
    /// 行情所属交易日(yyyy-MM-dd);非交易日展示上一交易日
    let dataDate: String?

    var id: String { def.secid }
}

// MARK: - 交易日推算

enum TradingDay {
    private static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return cal
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter
    }()

    /// 最近交易日(周末回退到周五;法定节假日无法本地判断,以接口返回数据为准)
    static func mostRecent(from date: Date = Date()) -> Date {
        let cal = calendar
        var day = cal.startOfDay(for: date)
        while cal.isDateInWeekend(day) {
            guard let previous = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return day
    }

    static func isWeekend(_ date: Date = Date()) -> Bool {
        calendar.isDateInWeekend(date)
    }

    static func string(_ date: Date) -> String {
        formatter.string(from: date)
    }

    /// 如 "星期五"
    static func weekdayLabel(_ date: Date) -> String {
        weekdayFormatter.string(from: date)
    }

    static func date(from string: String) -> Date? {
        formatter.date(from: string)
    }
}

// MARK: - 数据源模式

enum DataSourceMode: String, CaseIterable, Identifiable {
    case auto          // 东财优先,失败切腾讯
    case eastmoney     // 仅东财
    case tencent       // 仅腾讯

    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "自动(推荐)"
        case .eastmoney: return "仅东方财富"
        case .tencent: return "仅腾讯"
        }
    }
}

struct SectorQuote: Identifiable, Hashable {
    let name: String
    let code: String
    let changePercent: Double?

    var id: String { code }
}

struct StageReturn: Equatable, Identifiable {
    let label: String
    let percent: Double
    var id: String { label }
}

struct FundDetail: Equatable {
    let code: String
    let name: String
    let unitNav: Double?
    let navDate: String?
    let dayChangePercent: Double?
    /// 阶段涨幅(近1月/3月/6月/1年),蛋卷有则填充
    let stageReturns: [StageReturn]

    init(
        code: String,
        name: String,
        unitNav: Double? = nil,
        navDate: String? = nil,
        dayChangePercent: Double? = nil,
        stageReturns: [StageReturn] = []
    ) {
        self.code = code
        self.name = name
        self.unitNav = unitNav
        self.navDate = navDate
        self.dayChangePercent = dayChangePercent
        self.stageReturns = stageReturns
    }
}

struct NavPoint: Identifiable, Equatable {
    let date: String
    let nav: Double
    let changePercent: Double?

    var id: String { date }
}

// MARK: - 持仓

struct Holding: Identifiable, Codable, Hashable {
    var code: String
    var name: String
    /// 持有金额(昨日收盘市值口径)
    var amount: Double
    /// 成本金额,选填;填写后才能计算持有收益
    var cost: Double?

    var id: String { code }

    /// 当日盈亏 = 持有金额 × 当日涨跌幅
    static func dayPnl(amount: Double, dayPercent: Double) -> Double {
        amount * dayPercent / 100
    }

    /// 当前市值 = 持有金额 × (1 + 当日涨跌幅)
    static func marketValue(amount: Double, dayPercent: Double) -> Double {
        amount * (1 + dayPercent / 100)
    }

    /// 持有收益 = 当前市值 - 成本;未填成本时为 nil
    static func totalPnl(amount: Double, dayPercent: Double, cost: Double?) -> Double? {
        guard let cost, cost > 0 else { return nil }
        return marketValue(amount: amount, dayPercent: dayPercent) - cost
    }

    /// 持有收益率(%)
    static func totalPnlPercent(amount: Double, dayPercent: Double, cost: Double?) -> Double? {
        guard let cost, cost > 0 else { return nil }
        guard let pnl = totalPnl(amount: amount, dayPercent: dayPercent, cost: cost) else { return nil }
        return pnl / cost * 100
    }
}

// MARK: - 涨跌提醒

struct FundAlertCandidate: Equatable {
    let code: String
    let name: String
    let percent: Double
}

enum FundAlert {
    /// 当日涨跌幅越过阈值(绝对值)、且今天尚未提醒过的持仓基金
    static func candidates(
        holdings: [Holding],
        quotes: [String: FundDetail],
        threshold: Double,
        notifiedKeys: Set<String>,
        today: String
    ) -> [FundAlertCandidate] {
        guard threshold > 0 else { return [] }
        var result: [FundAlertCandidate] = []
        for holding in holdings {
            guard let percent = quotes[holding.code]?.dayChangePercent else { continue }
            guard abs(percent) >= threshold else { continue }
            let key = notifiedKey(code: holding.code, date: today)
            guard !notifiedKeys.contains(key) else { continue }
            result.append(FundAlertCandidate(code: holding.code, name: holding.name, percent: percent))
        }
        return result
    }

    static func notifiedKey(code: String, date: String) -> String {
        "fundbar.alert.\(date).\(code)"
    }
}

// MARK: - iCloud 同步载荷

/// 设置值的类型化包装(JSON 编解码需要区分类型)
enum SyncValue: Codable, Equatable {
    case string(String)
    case double(Double)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) { self = .bool(bool); return }
        if let double = try? container.decode(Double.self) { self = .double(double); return }
        self = .string(try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        }
    }
}

/// 同步到 iCloud Drive 的完整载荷;updatedAt 新者整体覆盖
struct SyncPayload: Codable, Equatable {
    var updatedAt: Date
    var holdings: [Holding]
    var settings: [String: SyncValue]

    /// 内容等值比较(忽略 updatedAt):用于防止 iCloud 同步乒乓循环
    static func == (lhs: SyncPayload, rhs: SyncPayload) -> Bool {
        lhs.holdings == rhs.holdings && lhs.settings == rhs.settings
    }

    static func build(from holdings: [Holding]) -> SyncPayload {
        let defaults = UserDefaults.standard
        var settings: [String: SyncValue] = [:]
        settings[SettingsKey.menuBarMode] = .string(defaults.string(forKey: SettingsKey.menuBarMode) ?? "icon")
        settings[SettingsKey.menuBarCodes] = .string(defaults.string(forKey: SettingsKey.menuBarCodes) ?? "1.000001")
        settings[SettingsKey.dataSource] = .string(defaults.string(forKey: SettingsKey.dataSource) ?? DataSourceMode.auto.rawValue)
        settings[SettingsKey.refreshInterval] = .double(defaults.double(forKey: SettingsKey.refreshInterval))
        settings[SettingsKey.alertEnabled] = .bool(defaults.bool(forKey: SettingsKey.alertEnabled))
        settings[SettingsKey.alertThreshold] = .double(defaults.double(forKey: SettingsKey.alertThreshold))
        return SyncPayload(updatedAt: Date(), holdings: holdings, settings: settings)
    }

    /// 应用远端载荷:设置写回 UserDefaults(@AppStorage 自动感知),持仓交给 MarketStore
    func apply() {
        let defaults = UserDefaults.standard
        for (key, value) in settings {
            switch value {
            case .string(let string): defaults.set(string, forKey: key)
            case .double(let double): defaults.set(double, forKey: key)
            case .bool(let bool): defaults.set(bool, forKey: key)
            }
        }
        Task { @MainActor in
            MarketStore.shared.replaceHoldings(holdings)
            await MarketStore.shared.refresh(showLoading: false)
        }
    }
}

// MARK: - 刷新策略(防封禁)

enum RefreshPolicy {
    /// 间隔 <= 0 表示仅手动刷新
    static func isScheduled(interval: Double) -> Bool {
        interval > 0
    }

    /// 周末行情静止,跳过自动刷新(工作日夜间的美股时段仍会刷新)
    static func autoRefreshAllowed(isWeekend: Bool) -> Bool {
        !isWeekend
    }

    /// 连续失败后的退避倍数:首次失败保持 1x,之后 2x → 3x → 4x 封顶
    static func backoffMultiplier(consecutiveFailures: Int) -> Double {
        min(Double(max(consecutiveFailures, 1)), 4)
    }

    /// 下一次允许自动刷新的时间
    static func nextAllowedAt(lastInterval: Double, consecutiveFailures: Int, from: Date) -> Date {
        let base = max(lastInterval, 30)
        return from.addingTimeInterval(base * backoffMultiplier(consecutiveFailures: consecutiveFailures))
    }

    /// 东财熔断:连续失败 ≥2 次且距上次失败不足冷却期(默认 5 分钟)时,自动模式先走腾讯
    static func eastMoneyInCooldown(consecutiveFailures: Int, lastFailureAt: Date?, now: Date = Date(), cooldown: TimeInterval = 300) -> Bool {
        guard consecutiveFailures >= 2, let lastFailureAt else { return false }
        return now.timeIntervalSince(lastFailureAt) < cooldown
    }
}

// MARK: - 设置键

enum SettingsKey {
    /// 菜单栏显示模式:"icon"(仅图标) | "iconText"(图标 + 涨跌摘要)
    static let menuBarMode = "fundbar.menubar.mode"
    /// 菜单栏摘要展示的指数 secid,逗号分隔,最多 3 个
    static let menuBarCodes = "fundbar.menubar.codes"
    /// 行情刷新间隔(秒)
    static let refreshInterval = "fundbar.refresh.interval"
    /// 持仓持久化
    static let holdings = "fundbar.holdings.v1"
    /// 涨跌提醒开关
    static let alertEnabled = "fundbar.alert.enabled"
    /// 提醒阈值(正数百分比,如 2.0 表示 ±2%)
    static let alertThreshold = "fundbar.alert.threshold"
    /// 已发送提醒的 key 列表(防重复)
    static let alertNotified = "fundbar.alert.notified"
    /// 行情数据源:"auto" | "eastmoney" | "tencent"
    static let dataSource = "fundbar.datasource"
    /// iCloud 同步开关
    static let icloudSyncEnabled = "fundbar.icloud.enabled"
}
