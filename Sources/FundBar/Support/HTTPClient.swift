import Foundation

/// 共享 HTTP 客户端:统一 UA/Referer、可重试错误、连接超时。
/// 行情接口是公开 GET,使用 ephemeral 会话避免缓存干扰。
struct HTTPClient {
    static let shared = HTTPClient()

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// 网络瞬断类错误,值得重试一次
    private static func isRetryable(_ code: URLError.Code) -> Bool {
        switch code {
        case .networkConnectionLost, .notConnectedToInternet, .timedOut,
             .cannotConnectToHost, .dnsLookupFailed, .cannotFindHost:
            return true
        default:
            return false
        }
    }

    func get(_ urlString: String, referer: String?) async throws -> Data {
        guard let url = URL(string: urlString) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        if let referer {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        var lastError: Error = APIError.badStatus(-1)
        for attempt in 0..<2 {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw APIError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
                }
                return data
            } catch {
                lastError = error
                if attempt == 0, let urlError = error as? URLError, Self.isRetryable(urlError.code) {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    continue
                }
                throw error
            }
        }
        throw lastError
    }
}

/// 把底层错误翻译成用户能看懂的中文提示
func friendlyNetworkMessage(_ error: Error) -> String {
    if let urlError = error as? URLError {
        switch urlError.code {
        case .networkConnectionLost:
            return "网络连接被中断(IPv6 异常网络的典型症状)"
        case .notConnectedToInternet:
            return "无网络连接"
        case .timedOut:
            return "请求超时"
        case .cannotFindHost, .cannotConnectToHost:
            return "无法连接服务器"
        case .dnsLookupFailed:
            return "域名解析失败"
        default:
            break
        }
    }
    return error.localizedDescription
}
