import Foundation

/// 东财基金系接口(无需登录):fundsuggest 搜索 + 天天基金新版批量估值。
struct EastmoneyFundAPI {
    static let shared = EastmoneyFundAPI()

    struct EstimateQuote: Equatable {
        let percent: Double
        /// 东财返回的估值所属日期，上海时间 yyyy-MM-dd。
        let dataDate: String
    }

    struct EstimateBatchResult {
        let quotes: [String: EstimateQuote]
        let failedBatchCount: Int
    }

    // MARK: - 基金搜索

    struct SearchHit: Identifiable, Equatable {
        let code: String
        let name: String
        var id: String { code }
    }

    struct SearchResponse: Decodable {
        struct Item: Decodable {
            let CODE: String?
            let NAME: String?
        }
        let Datas: [Item]?
    }

    /// 关键词搜索基金(名称/简拼/代码)
    func searchFunds(keyword: String) async throws -> [SearchHit] {
        guard let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return []
        }
        let urlString = "https://fundsuggest.eastmoney.com/FundSearch/api/FundSearchAPI.ashx?m=1&key=\(encoded)&pageindex=0&pagesize=8"
        let data = try await HTTPClient.shared.get(urlString, referer: "https://fund.eastmoney.com/")
        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        return (decoded.Datas ?? []).compactMap { item in
            guard let code = item.CODE, let name = item.NAME, !code.isEmpty else { return nil }
            return SearchHit(code: code, name: name)
        }
    }

    // MARK: - 盘中估值

    struct ValuationResponse: Decodable {
        struct Item: Decodable {
            let FCODE: String?
            let GSZZL: DanjuanAPI.FlexibleString?
            let GZTIME: DanjuanAPI.FlexibleString?
        }
        let data: [Item]?
        let errorCode: Int?
        let success: Bool?
    }

    /// 批量获取盘中估值。2026-10-03 验证的路径与字段：
    /// https://fundcomapi.tiantianfunds.com/mm/newCore/FundValuationLast
    /// FCODES=161725,001632,110022&FIELDS=FCODE,SHORTNAME,GSZZL,GZTIME,GSZ,NAV,PDATE
    /// GZTIME 如 "2026-09-30 15:00"；110022 的 GSZZL/GZTIME 均为 null。
    func fetchEstimateBatches(codes: [String]) async -> EstimateBatchResult {
        guard !codes.isEmpty else { return EstimateBatchResult(quotes: [:], failedBatchCount: 0) }
        var result: [String: EstimateQuote] = [:]
        var failedBatchCount = 0
        for start in stride(from: 0, to: codes.count, by: 50) {
            let batch = Array(codes[start..<min(start + 50, codes.count)])
            var rows: [String: EstimateQuote]?
            do {
                rows = try await fetchValuationBatch(codes: batch, host: "fundcomapi.tiantianfunds.com")
            } catch {
                rows = try? await fetchValuationBatch(codes: batch, host: "fundcomapi.eastmoney.com")
            }
            if let rows {
                result.merge(rows) { _, new in new }
            } else {
                failedBatchCount += 1
            }
        }
        return EstimateBatchResult(quotes: result, failedBatchCount: failedBatchCount)
    }

    func fetchEstimateQuotes(codes: [String]) async throws -> [String: EstimateQuote] {
        let result = await fetchEstimateBatches(codes: codes)
        if result.failedBatchCount > 0, result.quotes.isEmpty { throw APIError.badResponse }
        return result.quotes
    }

    private func fetchValuationBatch(codes: [String], host: String) async throws -> [String: EstimateQuote] {
        var components = URLComponents(string: "https://\(host)/mm/newCore/FundValuationLast")!
        components.queryItems = [
            URLQueryItem(name: "FCODES", value: codes.joined(separator: ",")),
            URLQueryItem(name: "FIELDS", value: "FCODE,SHORTNAME,GSZZL,GZTIME,GSZ,NAV,PDATE"),
        ]
        let data = try await HTTPClient.shared.get(components.url!.absoluteString, referer: nil)
        let response = try JSONDecoder().decode(ValuationResponse.self, from: data)
        guard response.success == true, response.errorCode == 0, let rows = response.data else {
            throw APIError.badResponse
        }
        var quotes: [String: EstimateQuote] = [:]
        for row in rows {
            guard let code = row.FCODE,
                  let percent = row.GSZZL?.doubleValue, percent.isFinite,
                  let date = FundQuotePolicy.sourceDay(row.GZTIME?.text) else { continue }
            quotes[code] = EstimateQuote(percent: percent, dataDate: date)
        }
        return quotes
    }

    /// 单只基金调用方仍可使用同一批量接口。
    func fetchEstimateQuote(code: String) async throws -> EstimateQuote? {
        try await fetchEstimateQuotes(codes: [code])[code]
    }

    /// 保留原有便捷接口，使用同一有日期的估值来源。
    func fetchEstimate(code: String) async throws -> Double? {
        try await fetchEstimateQuote(code: code)?.percent
    }
}
