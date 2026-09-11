import Foundation

// 极简测试骨架:不依赖 XCTest(无需完整 Xcode)。
// 编译为独立可执行文件运行,退出码 0 = 全部通过;安装完整 Xcode 后可迁移回 swift test。

enum TestRun {
    static var failureCount = 0
    static var checkCount = 0

    static func check(_ condition: Bool, _ message: String) {
        checkCount += 1
        if condition {
            print("  ✅ \(message)")
        } else {
            failureCount += 1
            print("  ❌ \(message)")
        }
    }

    static func checkEqual(_ actual: Double, _ expected: Double, accuracy: Double, _ message: String) {
        check(abs(actual - expected) <= accuracy, "\(message)(actual=\(actual), expected=\(expected))")
    }

    // MARK: - 持仓盈亏计算

    static func holdingMathTests() {
        print("持仓盈亏计算:")
        // 持有 10000,当日 -1.51% → 盈亏 -151,市值 9849;成本 11820 → 收益 -1971(-16.67%)
        checkEqual(Holding.dayPnl(amount: 10000, dayPercent: -1.51), -151, accuracy: 0.01, "当日盈亏")
        checkEqual(Holding.marketValue(amount: 10000, dayPercent: -1.51), 9849, accuracy: 0.01, "当前市值")
        checkEqual(Holding.totalPnl(amount: 10000, dayPercent: -1.51, cost: 11820) ?? 0, -1971, accuracy: 0.01, "持有收益")
        checkEqual(Holding.totalPnlPercent(amount: 10000, dayPercent: -1.51, cost: 11820) ?? 0, -16.67, accuracy: 0.01, "持有收益率")
        check(Holding.totalPnl(amount: 10000, dayPercent: 0, cost: nil) == nil, "未填成本时无持有收益")
        check(Holding.totalPnl(amount: 10000, dayPercent: 0, cost: 0) == nil, "成本为 0 时无持有收益")
    }

    // MARK: - 接口解码(样本来自 2026-09-11 实测返回)

    static func eastmoneyDecodeTests() {
        print("东财行情解码:")
        let json = """
        {"data":{"diff":[
            {"f2":3888.11,"f3":-1.18,"f4":-46.29,"f12":"000001","f14":"上证指数"},
            {"f2":"-","f3":"-","f4":"-","f12":"N225","f14":"日经225"}
        ]}}
        """
        do {
            let decoded = try JSONDecoder().decode(EastmoneyAPI.QuoteResponse.self, from: Data(json.utf8))
            let rows = decoded.data?.diff ?? []
            check(rows.count == 2, "diff 行数")
            checkEqual(rows[0].f2?.value ?? 0, 3888.11, accuracy: 0.001, "点位解析")
            checkEqual(rows[0].f3?.value ?? 0, -1.18, accuracy: 0.001, "涨跌幅解析")
            check(rows[1].f2?.value == nil, "休市时段 \"-\" 兼容为 nil")
            check(rows[1].f14 == "日经225", "名称解析")
        } catch {
            check(false, "解码异常:\(error)")
        }
    }

    static func danjuanDecodeTests() {
        print("蛋卷接口解码:")
        let detailJSON = """
        {"data":{"fd_code":"161725","fd_name":"招商中证白酒指数",
        "fund_derived":{"end_date":"2026-09-11","unit_nav":"0.5337","nav_grtd":"-1.5132"}}}
        """
        do {
            let decoded = try JSONDecoder().decode(DanjuanAPI.DetailResponse.self, from: Data(detailJSON.utf8))
            check(decoded.data?.fd_name == "招商中证白酒指数", "基金名称")
            checkEqual(decoded.data?.fund_derived?.unit_nav?.doubleValue ?? 0, 0.5337, accuracy: 0.0001, "单位净值")
            checkEqual(decoded.data?.fund_derived?.nav_grtd?.doubleValue ?? 0, -1.5132, accuracy: 0.0001, "当日涨跌幅")
            check(decoded.data?.fund_derived?.end_date == "2026-09-11", "净值日期")
        } catch {
            check(false, "详情解码异常:\(error)")
        }

        let historyJSON = """
        {"data":{"items":[
            {"date":"2026-09-11","nav":"0.5337","percentage":"-1.51","value":"0.5337"},
            {"date":"2026-09-10","nav":"0.5419","percentage":"-1.99","value":"0.5419"}
        ],"current_page":1,"size":3,"total_items":2752,"total_pages":918},"result_code":0}
        """
        do {
            let decoded = try JSONDecoder().decode(DanjuanAPI.HistoryResponse.self, from: Data(historyJSON.utf8))
            let items = decoded.data?.items ?? []
            check(items.count == 2, "history items 行数")
            checkEqual(items[0].nav?.doubleValue ?? 0, 0.5337, accuracy: 0.0001, "净值解析")
            checkEqual(items[0].percentage?.doubleValue ?? 0, -1.51, accuracy: 0.001, "涨跌幅解析")
            check(decoded.data?.total_pages == 918, "分页信息")
        } catch {
            check(false, "历史解码异常:\(error)")
        }
    }

    static func indexDefTests() {
        print("指数定义:")
        check(IndexDef.all.count == 9, "共 9 个指数(A股3 + 亚太3 + 美股3)")
        let secids = Set(IndexDef.all.map(\.secid))
        check(secids.contains("100.N225"), "日经225")
        check(secids.contains("100.KS11"), "韩国KOSPI")
        check(secids.contains("100.NDX"), "纳斯达克(注意代码是 NDX 不是 IXIC)")
        check(
            IndexDef(name: "", shortName: "", secid: "1.000001", tencentCode: "sh000001", region: .cn).codePart == "000001",
            "codePart 提取尾段代码"
        )
        // 降级源覆盖:除日经/KOSPI 外均有腾讯代码
        let withTencent = IndexDef.all.compactMap(\.tencentCode)
        check(withTencent.count == 7, "腾讯备用源覆盖 7/9 指数(日经/KOSPI 无免费替代)")
        check(!withTencent.contains(where: { $0.hasPrefix("jp") || $0.hasPrefix("kr") }), "日经/KOSPI 不在腾讯源内")
    }

    // MARK: - 腾讯降级源解析(样本来自 2026-09-11 实测)

    static func tencentParseTests() {
        print("腾讯行情解析:")
        let sample = """
        v_pv_none_match="1";
        v_sh000001="1~上证指数~000001~3888.11~3934.40~3910.92~579123145~0~0~0.00~0~0.00~0~0.00~0~0.00~0~0.00~0~0.00~0~0.00~0~0.00~0~20260911161403~-46.29~-1.18~3812.32~3934.40~1~.jpg";
        v_usDJI="200~道琼斯~.DJI~52573.29~52064.10~52204.46~354468410~0~0~52442.83~0~0~0~0~0~0~0~0~0~52671.60~0~0~0~0~0~0~0~0~0~~2026-09-11";
        """
        let parsed = TencentAPI.parse(sample)
        check(parsed.count == 2, "有效行解析(跳过 none_match)")
        let sh = parsed["sh000001"]
        check(sh?.name == "上证指数", "名称字段")
        checkEqual(sh?.price ?? 0, 3888.11, accuracy: 0.001, "现价")
        checkEqual(sh?.change ?? 0, -46.29, accuracy: 0.01, "涨跌额(现价-昨收)")
        checkEqual(sh?.changePercent ?? 0, -1.1766, accuracy: 0.001, "涨跌幅推算")
        let dji = parsed["usDJI"]
        checkEqual(dji?.price ?? 0, 52573.29, accuracy: 0.001, "美股现价")
        check(dji?.name == "道琼斯", "美股名称")
    }

    static func alertTests() {
        print("涨跌提醒:")
        let holdings = [
            Holding(code: "161725", name: "招商中证白酒A", amount: 10000, cost: nil),
            Holding(code: "000217", name: "华安黄金C", amount: 36000, cost: nil),
        ]
        let quotes = [
            "161725": FundDetail(code: "161725", name: "招商中证白酒A", unitNav: 0.5337, navDate: "2026-09-11", dayChangePercent: -2.15),
            "000217": FundDetail(code: "000217", name: "华安黄金C", unitNav: 5.11, navDate: "2026-09-11", dayChangePercent: 0.42),
        ]
        let found = FundAlert.candidates(holdings: holdings, quotes: quotes, threshold: 2.0, notifiedKeys: [], today: "2026-09-11")
        check(found.count == 1 && found.first?.code == "161725", "仅越过阈值的基金进入提醒(-2.15% 越过 ±2%,0.42% 不触发)")
        let again = FundAlert.candidates(
            holdings: holdings, quotes: quotes, threshold: 2.0,
            notifiedKeys: [FundAlert.notifiedKey(code: "161725", date: "2026-09-11")],
            today: "2026-09-11"
        )
        check(again.isEmpty, "当天已提醒过不再重复提醒")
        let thresholdZero = FundAlert.candidates(holdings: holdings, quotes: quotes, threshold: 0, notifiedKeys: [], today: "2026-09-11")
        check(thresholdZero.isEmpty, "阈值为 0 不触发任何提醒")
        let positive = FundAlert.candidates(holdings: holdings, quotes: quotes, threshold: 2.0, notifiedKeys: [], today: "2026-09-12")
        check(positive.count == 1, "跨天后重新提醒")
        check(FundAlert.notifiedKey(code: "161725", date: "2026-09-11") == "fundbar.alert.2026-09-11.161725", "去重 key 格式")
    }

    static func runAll() {
        holdingMathTests()
        eastmoneyDecodeTests()
        danjuanDecodeTests()
        indexDefTests()
        tencentParseTests()
        alertTests()
        print("")
        if failureCount == 0 {
            print("全部 \(checkCount) 项检查通过 ✅")
        } else {
            print("\(failureCount)/\(checkCount) 项检查失败 ❌")
            exit(1)
        }
    }
}

@main
struct TestMain {
    static func main() {
        TestRun.runAll()
    }
}
