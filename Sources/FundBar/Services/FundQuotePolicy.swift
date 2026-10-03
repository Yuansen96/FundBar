import Foundation

/// 只给“今日盈亏”和涨跌提醒使用有明确上海日期的当日涨跌。
/// 历史净值本身仍可按原始日期展示；周末、节假日不把上一交易日涨跌当作今日涨跌。
enum FundQuotePolicy {
    struct EffectivePercent: Equatable {
        let percent: Double
        let isEstimate: Bool
    }

    /// 接口日期可能是 yyyy-MM-dd 或 yyyy-MM-dd HH:mm:ss，拒绝缺失和无效日期。
    static func sourceDay(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let value = String(rawValue.prefix(10))
        guard value.count == 10,
              let date = TradingDay.date(from: value),
              TradingDay.string(date) == value else { return nil }
        return value
    }

    static func effectivePercent(
        navDate: String?,
        navPercent: Double?,
        estimateDate: String?,
        estimatePercent: Double?,
        now: Date = Date()
    ) -> EffectivePercent? {
        let today = TradingDay.string(now)
        if sourceDay(estimateDate) == today,
           let estimatePercent, estimatePercent.isFinite {
            return EffectivePercent(percent: estimatePercent, isEstimate: true)
        }
        if sourceDay(navDate) == today,
           let navPercent, navPercent.isFinite {
            return EffectivePercent(percent: navPercent, isEstimate: false)
        }
        return nil
    }
}
