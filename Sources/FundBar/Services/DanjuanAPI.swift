import Foundation

/// 蛋卷基金接口(非官方):基金详情与历史净值。
/// 替代已失效的天天基金 fundgz 估值接口。
struct DanjuanAPI {
    static let shared = DanjuanAPI()

    /// 蛋卷的净值/涨跌幅字段是字符串,兼容极端情况下的数字
    enum FlexibleString: Decodable {
        case string(String)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(String.self) {
                self = .string(value)
            } else {
                self = .string(String(try container.decode(Double.self)))
            }
        }

        var text: String {
            if case .string(let value) = self { return value }
            return ""
        }

        var doubleValue: Double? { Double(text) }
    }

    struct DetailResponse: Decodable {
        struct Derived: Decodable {
            let end_date: String?
            let unit_nav: FlexibleString?
            let nav_grtd: FlexibleString?
        }
        struct Payload: Decodable {
            let fd_code: String?
            let fd_name: String?
            let fund_derived: Derived?
        }
        let data: Payload?
    }

    struct HistoryResponse: Decodable {
        struct Item: Decodable {
            let date: String?
            let nav: FlexibleString?
            let percentage: FlexibleString?
        }
        struct Payload: Decodable {
            let items: [Item]?
            let total_pages: Int?
        }
        let data: Payload?
    }

    private func get(_ urlString: String) async throws -> Data {
        try await HTTPClient.shared.get(urlString, referer: "https://danjuanfunds.com/")
    }

    /// 基金详情:名称、最新净值、当日涨跌幅
    func fetchFundDetail(code: String) async throws -> FundDetail {
        let data = try await get("https://danjuanfunds.com/djapi/fund/\(code)")
        let decoded = try JSONDecoder().decode(DetailResponse.self, from: data)
        let payload = decoded.data
        return FundDetail(
            code: payload?.fd_code ?? code,
            name: payload?.fd_name ?? code,
            unitNav: payload?.fund_derived?.unit_nav?.doubleValue,
            navDate: payload?.fund_derived?.end_date,
            dayChangePercent: payload?.fund_derived?.nav_grtd?.doubleValue
        )
    }

    /// 历史净值(按交易日,时间升序返回)。
    /// 接口按页返回且单页上限未知,这里循环分页直到攒够 maxPoints。
    func fetchNavHistory(code: String, maxPoints: Int) async throws -> [NavPoint] {
        var collected: [NavPoint] = []
        var page = 1
        let pageSize = 500
        while collected.count < maxPoints {
            let urlString = "https://danjuanfunds.com/djapi/fund/nav/history/\(code)?page=\(page)&size=\(pageSize)"
            let data = try await get(urlString)
            let decoded = try JSONDecoder().decode(HistoryResponse.self, from: data)
            let items = decoded.data?.items ?? []
            guard !items.isEmpty else { break }
            for item in items {
                guard let date = item.date, let nav = item.nav?.doubleValue else { continue }
                collected.append(
                    NavPoint(date: date, nav: nav, changePercent: item.percentage?.doubleValue)
                )
            }
            if page >= (decoded.data?.total_pages ?? 0) { break }
            page += 1
        }
        return Array(collected.reversed())
    }
}
