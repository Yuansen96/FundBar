import Foundation

enum APIError: LocalizedError {
    case badStatus(Int)
    case invalidURL
    case badResponse

    var errorDescription: String? {
        switch self {
        case .badStatus(let code): return "HTTP \(code)"
        case .invalidURL: return "接口地址无效"
        case .badResponse: return "响应格式异常"
        }
    }
}

/// 东方财富行情接口(非官方)。
/// 指数 ulist、行业板块 clist 均无需鉴权;字段含义见 README「数据来源」。
struct EastmoneyAPI {
    static let shared = EastmoneyAPI()

    /// fltt=2 时 f2/f3/f4 通常是数字,休市时段可能返回 "-",需要兼容
    enum FlexibleNumber: Decodable {
        case double(Double)
        case string(String)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Double.self) {
                self = .double(value)
            } else {
                self = .string(try container.decode(String.self))
            }
        }

        var value: Double? {
            if case .double(let value) = self { return value }
            return nil
        }
    }

    struct QuoteResponse: Decodable {
        struct Diff: Decodable {
            let f2: FlexibleNumber?
            let f3: FlexibleNumber?
            let f4: FlexibleNumber?
            let f12: String?
            let f14: String?
        }
        struct Payload: Decodable { let diff: [Diff]? }
        let data: Payload?
    }

    struct Quote {
        let price: Double?
        let change: Double?
        let changePercent: Double?
    }

    private func get(_ urlString: String, referer: String) async throws -> Data {
        try await HTTPClient.shared.get(urlString, referer: referer)
    }

    /// 批量拉取指数行情。返回以「secid 尾段代码」和「指数名称」两种 key 的映射,
    /// 因为接口 f12 只返回代码尾段(如 1.000001 -> "000001",100.N225 -> "N225")。
    func fetchQuotes(secids: [String]) async throws -> [String: Quote] {
        var components = URLComponents(string: "https://push2.eastmoney.com/api/qt/ulist.np/get")!
        components.queryItems = [
            URLQueryItem(name: "fltt", value: "2"),
            URLQueryItem(name: "secids", value: secids.joined(separator: ",")),
            URLQueryItem(name: "fields", value: "f2,f3,f4,f12,f14"),
        ]
        let data = try await get(components.url!.absoluteString, referer: "https://quote.eastmoney.com/")
        let decoded = try JSONDecoder().decode(QuoteResponse.self, from: data)
        var result: [String: Quote] = [:]
        for row in decoded.data?.diff ?? [] {
            let quote = Quote(
                price: row.f2?.value,
                change: row.f4?.value,
                changePercent: row.f3?.value
            )
            if let code = row.f12 { result[code] = quote }
            if let name = row.f14 { result[name] = quote }
        }
        return result
    }

    /// 行业板块涨跌榜(fs=m:90+t:2,共 496 个板块)。
    /// po=1 按涨跌幅降序(涨幅榜),po=0 升序(跌幅榜)。
    func fetchSectorRank(ascending: Bool, count: Int) async throws -> [SectorQuote] {
        var components = URLComponents(string: "https://push2.eastmoney.com/api/qt/clist/get")!
        components.queryItems = [
            URLQueryItem(name: "pn", value: "1"),
            URLQueryItem(name: "pz", value: String(count)),
            URLQueryItem(name: "po", value: ascending ? "0" : "1"),
            URLQueryItem(name: "np", value: "1"),
            URLQueryItem(name: "fltt", value: "2"),
            URLQueryItem(name: "fid", value: "f3"),
            URLQueryItem(name: "fs", value: "m:90+t:2"),
            URLQueryItem(name: "fields", value: "f3,f12,f14"),
        ]
        let data = try await get(components.url!.absoluteString, referer: "https://quote.eastmoney.com/")
        let decoded = try JSONDecoder().decode(QuoteResponse.self, from: data)
        return (decoded.data?.diff ?? []).compactMap { row in
            guard let name = row.f14, let code = row.f12 else { return nil }
            return SectorQuote(name: name, code: code, changePercent: row.f3?.value)
        }
    }
}
