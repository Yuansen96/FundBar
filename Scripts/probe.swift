import Foundation

// 网络诊断探针:用与 App 完全相同的 API 层代码在控制台复现请求
// 用法:swiftc probe.swift Models.swift EastmoneyAPI.swift DanjuanAPI.swift -o probe && ./probe

@main
struct Probe {
    static func main() async {
        print("=== [1] 东财指数 ulist ===")
        do {
            let quotes = try await EastmoneyAPI.shared.fetchQuotes(secids: ["1.000001", "100.N225"])
            for (key, quote) in quotes.sorted(by: { $0.key < $1.key }) {
                print("  OK \(key): \(quote.price ?? -1) \(quote.changePercent ?? -99)%")
            }
        } catch {
            print("  FAIL: \(error)")
            print("  详型: \(String(describing: type(of: error)))")
            if let ns = error as NSError? { print("  domain=\(ns.domain) code=\(ns.code) \(ns.userInfo)") }
        }

        print("=== [2] 东财板块 clist ===")
        do {
            let sectors = try await EastmoneyAPI.shared.fetchSectorRank(ascending: false, count: 3)
            print("  OK: \(sectors.map { "\($0.name) \($0.changePercent ?? -99)%" }.joined(separator: " | "))")
        } catch {
            print("  FAIL: \(error)")
            if let ns = error as NSError? { print("  domain=\(ns.domain) code=\(ns.code) \(ns.userInfo)") }
        }

        print("=== [3] 蛋卷详情 ===")
        do {
            let detail = try await DanjuanAPI.shared.fetchFundDetail(code: "161725")
            print("  OK: \(detail.name) 净值\(detail.unitNav ?? -1) (\(detail.navDate ?? "-")) \(detail.dayChangePercent ?? -99)%")
        } catch {
            print("  FAIL: \(error)")
            if let ns = error as NSError? { print("  domain=\(ns.domain) code=\(ns.code) \(ns.userInfo)") }
        }

        print("=== [4] 蛋卷历史 ===")
        do {
            let history = try await DanjuanAPI.shared.fetchNavHistory(code: "161725", maxPoints: 30)
            print("  OK: \(history.count) 条,首 \(history.first?.date ?? "-") 尾 \(history.last?.date ?? "-")")
        } catch {
            print("  FAIL: \(error)")
            if let ns = error as NSError? { print("  domain=\(ns.domain) code=\(ns.code) \(ns.userInfo)") }
        }

        print("=== [5] 原始 URLSession 直连(排除 API 层)===")
        do {
            let url = URL(string: "https://push2.eastmoney.com/api/qt/ulist.np/get?fltt=2&secids=1.000001&fields=f2,f3,f12,f14")!
            let (data, resp) = try await URLSession.shared.data(from: url)
            print("  OK: \((resp as? HTTPURLResponse)?.statusCode ?? -1), \(data.count) bytes")
        } catch {
            print("  FAIL: \(error)")
            if let ns = error as NSError? { print("  domain=\(ns.domain) code=\(ns.code) \(ns.userInfo)") }
        }

        exit(0)
    }
}
