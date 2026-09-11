import SwiftUI

// MARK: - 配色(国内习惯:红涨绿跌)

enum CnStyle {
    static let up = Color(red: 0.88, green: 0.24, blue: 0.24)
    static let down = Color(red: 0.04, green: 0.63, blue: 0.43)
    static let flat = Color.secondary

    static func color(for value: Double?) -> Color {
        guard let value else { return flat }
        if value > 0 { return up }
        if value < 0 { return down }
        return flat
    }
}

// MARK: - 数字格式化

extension Double {
    /// +1.24% / -1.18%
    var percentText: String { String(format: "%+.2f%%", self) }
    /// 两位小数
    var priceText: String { String(format: "%.2f", self) }
    /// +46.29 / -46.29
    var changeText: String { String(format: "%+.2f", self) }
    /// ¥1,234(整数千分位)
    var yuanText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let text = formatter.string(from: NSNumber(value: self)) ?? String(format: "%.0f", self)
        return "¥" + text
    }
}

extension Optional where Wrapped == Double {
    var percentText: String { self?.percentText ?? "--" }
    var priceText: String { self?.priceText ?? "--" }
    var changeText: String { self?.changeText ?? "--" }
}

// MARK: - 日期解析(蛋卷净值日期 "yyyy-MM-dd")

extension NavPoint {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return formatter
    }()

    var dateValue: Date? {
        Self.formatter.date(from: date)
    }
}
