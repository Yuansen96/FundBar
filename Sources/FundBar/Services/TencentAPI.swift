import Foundation

/// 腾讯行情接口(qt.gtimg.cn,v4-only 解析,可作为东财双栈域名失败时的降级源)。
/// 响应为 GBK 编码文本,行格式:v_sh000001="1~上证指数~000001~3888.11~3934.40~..."
/// 字段:[1]=名称 [3]=现价 [4]=昨收,涨跌幅由现价/昨收推算(不依赖易变字段序号)。
struct TencentAPI {
    static let shared = TencentAPI()

    struct Quote {
        let name: String
        let price: Double?
        let change: Double?
        let changePercent: Double?
        /// 行情日期(yyyy-MM-dd),行内无法解析时为 nil
        let dataDate: String?
    }

    func fetchQuotes(codes: [String]) async throws -> [String: Quote] {
        guard !codes.isEmpty else { return [:] }
        let urlString = "https://qt.gtimg.cn/q=\(codes.joined(separator: ","))"
        let data = try await HTTPClient.shared.get(urlString, referer: "https://gu.qq.com/")
        guard let text = String(data: data, encoding: Self.gbkEncoding) else {
            throw APIError.badResponse
        }
        return Self.parse(text)
    }

    /// GB_18030(GNK 兼容)编码
    static let gbkEncoding = String.Encoding(
        cfStringEncodings: .GB_18030_2000
    )

    /// 纯解析函数(供测试):输入已解码文本,输出 code -> Quote
    static func parse(_ text: String) -> [String: Quote] {
        var result: [String: Quote] = [:]
        for line in text.split(separator: ";") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("v_"), trimmed.contains("=\"") else { continue }
            let code = trimmed.dropFirst(2).prefix(while: { $0 != "=" })
            let content = trimmed.drop { $0 != "=" }.dropFirst().trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let fields = content.split(separator: "~", omittingEmptySubsequences: false).map(String.init)
            guard fields.count > 4, let price = Double(fields[3]), let prevClose = Double(fields[4]), prevClose != 0 else {
                continue
            }
            let change = price - prevClose
            let percent = change / prevClose * 100
            result[String(code)] = Quote(
                name: fields.count > 1 ? fields[1] : String(code),
                price: price,
                change: change,
                changePercent: percent,
                dataDate: extractDate(content)
            )
        }
        return result
    }

    /// 从行内容提取行情日期:A股为 14 位时间戳(20260911161403),美股为 "2026-09-11"。
    /// 14 位正则限定 2020-2039 年开头,避免误匹配成交量等大数字。
    static func extractDate(_ content: String) -> String? {
        if let range = content.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) {
            return String(content[range])
        }
        if let range = content.range(of: #"20[2-3]\d{11}"#, options: .regularExpression) {
            let digits = String(content[range])
            return "\(digits.prefix(4))-\(digits.dropFirst(4).prefix(2))-\(digits.dropFirst(6).prefix(2))"
        }
        return nil
    }
}

private extension String.Encoding {
    /// String.Encoding(cfStringEncodings:) 便捷构造
    init(cfStringEncodings: CFStringEncodings) {
        self = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cfStringEncodings.rawValue))
        )
    }
}
