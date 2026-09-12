import Foundation

/// 东财基金系接口(养基宝/天天基金同款公开接口,无需登录):
/// fundsuggest 搜索 + fundmobapi 盘中估值。
struct EastmoneyFundAPI {
    static let shared = EastmoneyFundAPI()

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

    struct EstimateResponse: Decodable {
        struct Data_: Decodable {
            let GSZ: DanjuanAPI.FlexibleString?
            let GSZZL: DanjuanAPI.FlexibleString?
        }
        let Datas: Data_?
    }

    /// 盘中估算涨跌幅(%);休市或接口未提供时返回 nil
    func fetchEstimate(code: String) async throws -> Double? {
        let urlString = "https://fundmobapi.eastmoney.com/FundMNewApi/FundMNFInfo?FCODE=\(code)&deviceid=FUNDBAR-\(code)&plat=Android&product=EFund&Version=6.2.8&Uid=&CompanyCode=&usetype=0"
        let data = try await HTTPClient.shared.get(urlString, referer: nil)
        let decoded = try JSONDecoder().decode(EstimateResponse.self, from: data)
        guard let text = decoded.Datas?.GSZZL?.text else { return nil }
        return Double(text)
    }
}
