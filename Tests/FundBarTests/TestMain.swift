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
        let holdings = [
            Holding(code: "A", name: "A", amount: 10000, cost: 9000),
            Holding(code: "B", name: "B", amount: 5000, cost: nil),
        ]
        let missingQuote = PortfolioSummary(holdings: holdings, percents: ["A": 2])
        checkEqual(missingQuote.amount, 15000, accuracy: 0.01, "缺行情时仍显示持仓金额")
        check(missingQuote.dayPnl == nil && missingQuote.missingQuoteCount == 1, "缺行情时不显示误导性的当日盈亏")
        let missingCost = PortfolioSummary(holdings: holdings, percents: ["A": 2, "B": -1])
        checkEqual(missingCost.dayPnl ?? 0, 150, accuracy: 0.01, "行情齐全时汇总当日盈亏")
        check(missingCost.totalPnl == nil && missingCost.missingCostCount == 1, "成本不齐时不混算持有收益")
        let complete = PortfolioSummary(
            holdings: [holdings[0], Holding(code: "B", name: "B", amount: 5000, cost: 4500)],
            percents: ["A": 2, "B": -1]
        )
        checkEqual(complete.totalPnl ?? 0, 1650, accuracy: 0.01, "成本齐全时计算持有收益")
        checkEqual(complete.totalPnlPercent ?? 0, 1650 / 13500 * 100, accuracy: 0.01, "成本齐全时计算收益率")
        check((-151.0).yuanText.hasPrefix("-¥"), "负金额符号显示在人民币符号前")
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

    static func tradingDayTests() {
        print("交易日推算:")
        func shanghaiDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
            var comps = DateComponents()
            comps.year = year; comps.month = month; comps.day = day; comps.hour = 12
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
            return cal.date(from: comps)!
        }
        // 2026-09-12 周六、09-13 周日、09-11 周五、09-09 周三
        let saturday = shanghaiDate(2026, 9, 12)
        let sunday = shanghaiDate(2026, 9, 13)
        let friday = shanghaiDate(2026, 9, 11)
        let wednesday = shanghaiDate(2026, 9, 9)
        check(TradingDay.isWeekend(saturday), "9-12 是周末(周六)")
        check(!TradingDay.isWeekend(friday), "9-11 是工作日(周五)")
        check(TradingDay.string(TradingDay.mostRecent(from: saturday)) == "2026-09-11", "周六回退到周五 09-11")
        check(TradingDay.string(TradingDay.mostRecent(from: sunday)) == "2026-09-11", "周日回退到周五 09-11")
        check(TradingDay.string(TradingDay.mostRecent(from: wednesday)) == "2026-09-09", "周三保持当天")
        check(TradingDay.weekdayLabel(friday) == "星期五", "星期标签本地化")
    }

    static func tencentDateTests() {
        print("腾讯日期解析:")
        check(
            TencentAPI.extractDate("1~上证指数~000001~3888.11~3934.40~0~20260911161403~-46.29~-1.18") == "2026-09-11",
            "A股 14 位时间戳解析"
        )
        check(
            TencentAPI.extractDate("200~道琼斯~.DJI~52573.29~52064.10~52204.46~~2026-09-11") == "2026-09-11",
            "美股 yyyy-MM-dd 解析"
        )
        check(
            TencentAPI.extractDate("100~恒生指数~HSI~24805.630~24954.470~22843055.8745~0") == nil,
            "成交量等大数字不误判为日期"
        )
        check(DataSourceMode(rawValue: "tencent") == .tencent, "数据源模式解析")
        check(DataSourceMode(rawValue: "unknown") == nil, "非法数据源回落 auto")
    }

    static func alertTests() {
        print("涨跌提醒:")
        let holdings = [
            Holding(code: "161725", name: "招商中证白酒A", amount: 10000, cost: nil),
            Holding(code: "000217", name: "华安黄金C", amount: 36000, cost: nil),
        ]
        let percents = ["161725": -2.15, "000217": 0.42]
        let found = FundAlert.candidates(holdings: holdings, percents: percents, threshold: 2.0, notifiedKeys: [], today: "2026-09-11")
        check(found.count == 1 && found.first?.code == "161725", "仅越过阈值的基金进入提醒(-2.15% 越过 ±2%,0.42% 不触发)")
        let again = FundAlert.candidates(
            holdings: holdings, percents: percents, threshold: 2.0,
            notifiedKeys: [FundAlert.notifiedKey(code: "161725", date: "2026-09-11")],
            today: "2026-09-11"
        )
        check(again.isEmpty, "当天已提醒过不再重复提醒")
        let thresholdZero = FundAlert.candidates(holdings: holdings, percents: percents, threshold: 0, notifiedKeys: [], today: "2026-09-11")
        check(thresholdZero.isEmpty, "阈值为 0 不触发任何提醒")
        let positive = FundAlert.candidates(holdings: holdings, percents: percents, threshold: 2.0, notifiedKeys: [], today: "2026-09-12")
        check(positive.count == 1, "跨天后重新提醒")
        check(FundAlert.candidates(holdings: holdings, percents: [:], threshold: 2.0, notifiedKeys: [], today: "2026-09-12").isEmpty, "无有效当日行情时不提醒")
        check(FundAlert.candidates(holdings: holdings, percents: ["161725": .nan], threshold: 2.0, notifiedKeys: [], today: "2026-09-12").isEmpty, "异常涨跌幅不提醒")
        check(FundAlert.notifiedKey(code: "161725", date: "2026-09-11") == "fundbar.alert.2026-09-11.161725", "去重 key 格式")
    }

    static func holdingSortingTests() {
        print("持仓排序:")
        let holdings = [
            Holding(code: "A", name: "A", amount: 1000, cost: 800),
            Holding(code: "B", name: "B", amount: 2000, cost: nil),
            Holding(code: "C", name: "C", amount: 1500, cost: 1000),
            Holding(code: "D", name: "D", amount: 1000, cost: 800),
        ]
        let percents = ["A": 2.0, "B": -1.0, "D": 2.0]
        func codes(_ order: HoldingSortOrder, _ values: [String: Double] = percents) -> [String] {
            HoldingSorting.sorted(holdings, by: order, percents: values).map(\.code)
        }
        check(codes(.original) == ["A", "B", "C", "D"], "默认保持保存顺序")
        check(codes(.dayPercent) == ["A", "D", "B", "C"], "按涨跌幅排序，缺行情置底且同值稳定")
        check(codes(.dayPnl) == ["A", "D", "B", "C"], "按当日盈亏排序")
        check(codes(.amount) == ["B", "C", "A", "D"], "按持有金额排序")
        check(codes(.totalPnl) == ["A", "D", "B", "C"], "按持有收益排序，缺成本置底")
        check(codes(.dayPercent, ["A": .nan, "B": -1.0, "D": 2.0]) == ["D", "B", "A", "C"], "异常涨跌幅按缺行情处理")
    }

    static func menuBarRendererTests() {
        print("菜单栏摘要渲染:")
        let quotes = [
            IndexQuote(
                def: IndexDef(name: "上证指数", shortName: "上证", secid: "1.000001", tencentCode: "sh000001", region: .cn),
                price: 3888.11, change: -46.29, changePercent: -1.18, dataDate: "2026-09-11"
            ),
            IndexQuote(
                def: IndexDef(name: "日经225", shortName: "日经", secid: "100.N225", tencentCode: nil, region: .asia),
                price: nil, change: nil, changePercent: nil, dataDate: nil
            ),
        ]
        let text = MenuBarSummaryRenderer.attributedText(for: quotes)
        check(text.length > 0, "有涨跌数据时输出非空摘要")
        check(text.string.contains("上证") && text.string.contains("-1.18%"), "包含名称与涨跌幅")
        check(!text.string.contains("日经"), "无数据指数不进摘要")
        let empty = MenuBarSummaryRenderer.attributedText(for: quotes.filter { $0.price == nil })
        check(empty.length == 0, "全部无数据时输出空摘要")
    }

    static func sparklineAndStageTests() {
        print("迷你走势与阶段涨幅:")
        // 腾讯日线 JSON(数字/字符串混合类型)
        let klineJSON = """
        {"code":0,"data":{"sh000001":{"qfqday":[
            ["2026-09-09","3910.92","3934.40","3934.40","3890.10","100"],
            ["2026-09-10",3888.11,3934.40,3940.00,3852.03,"200"],
            ["2026-09-11","3852.03","3888.11","3890.00","3800.00","300"]
        ]}}}
        """
        do {
            let closes = try TencentAPI.parseDailyCloses(from: Data(klineJSON.utf8))
            check(closes.count == 3, "日线行数")
            checkEqual(closes[0], 3934.40, accuracy: 0.001, "qfqday 收盘价(字符串)")
            checkEqual(closes[1], 3934.40, accuracy: 0.001, "day 收盘价(数字混合)")
            checkEqual(closes[2], 3888.11, accuracy: 0.001, "最新收盘价")
        } catch {
            check(false, "日线解析异常:\(error)")
        }

        // 蛋卷阶段涨幅
        let detailJSON = """
        {"data":{"fd_code":"161725","fd_name":"招商中证白酒指数","fund_derived":{"end_date":"2026-09-11",
        "unit_nav":"0.5337","nav_grtd":"-1.5132","nav_grl1m":"-6.74","nav_grl3m":"-2.14","nav_grl6m":"-18.93","nav_grl1y":"-36.31"}}}
        """
        do {
            let decoded = try JSONDecoder().decode(DanjuanAPI.DetailResponse.self, from: Data(detailJSON.utf8))
            let derived = decoded.data?.fund_derived
            checkEqual(derived?.nav_grl1m?.doubleValue ?? 0, -6.74, accuracy: 0.001, "近1月涨幅字段")
            check(derived?.nav_grl1y?.doubleValue == -36.31, "近1年涨幅字段")
        } catch {
            check(false, "详情解析异常:\(error)")
        }
    }

    static func searchAndEstimateTests() {
        print("基金搜索与估值解析:")
        // fundsuggest 搜索样本(2026-09-12 实测)
        let searchJSON = """
        {"ErrCode":0,"ErrMsg":"fromes","Datas":[
            {"CODE":"012414","NAME":"招商中证白酒指数(LOF)C","JP":"ZSZZBJZSLOFC","CATEGORY":700},
            {"CODE":"161725","NAME":"招商中证白酒指数(LOF)A","JP":"ZSZZBJZSLOFA","CATEGORY":700}
        ]}
        """
        do {
            let decoded = try JSONDecoder().decode(EastmoneyFundAPI.SearchResponse.self, from: Data(searchJSON.utf8))
            let hits = (decoded.Datas ?? []).compactMap { item -> EastmoneyFundAPI.SearchHit? in
                guard let code = item.CODE, let name = item.NAME else { return nil }
                return EastmoneyFundAPI.SearchHit(code: code, name: name)
            }
            check(hits.count == 2, "搜索结果条数")
            check(hits.first?.code == "012414", "搜索代码字段")
            check(hits.last?.name == "招商中证白酒指数(LOF)A", "搜索名称字段")
        } catch {
            check(false, "搜索解析异常:\(error)")
        }

        // 新批量估值样本：有的基金字段为空，历史日期不能充作今日估值。
        do {
            let sample = #"{"data":[{"FCODE":"161725","GSZZL":2.87,"GZTIME":"2026-09-30 15:00"},{"FCODE":"110022","GSZZL":null,"GZTIME":null}],"errorCode":0,"success":true}"#
            let response = try JSONDecoder().decode(EastmoneyFundAPI.ValuationResponse.self, from: Data(sample.utf8))
            check(response.success == true && response.errorCode == 0, "批量估值响应状态")
            check(response.data?.count == 2, "批量估值两只基金")
            checkEqual(response.data?.first?.GSZZL?.doubleValue ?? 0, 2.87, accuracy: 0.001, "数字估值涨跌幅解析")
            check(FundQuotePolicy.sourceDay(response.data?.first?.GZTIME?.text) == "2026-09-30", "估值源时间提取日期")
            check(response.data?.last?.GSZZL == nil && response.data?.last?.GZTIME == nil, "空估值字段安全忽略")
        } catch {
            check(false, "估值解析异常:\(error)")
        }
    }

    static func fundQuoteFreshnessTests() {
        print("基金行情时效:")
        let friday = TradingDay.date(from: "2026-09-11")!
        let saturday = TradingDay.date(from: "2026-09-12")!
        check(FundQuotePolicy.sourceDay("2026-02-30 12:00") == nil, "无效源日期拒绝")
        check(FundQuotePolicy.sourceDay(nil) == nil, "缺少源日期拒绝")
        check(FundQuotePolicy.effectivePercent(navDate: "2026-09-11", navPercent: -2, estimateDate: nil, estimatePercent: nil, now: friday)?.percent == -2, "当日净值可参与今日盈亏")
        check(FundQuotePolicy.effectivePercent(navDate: "2026-09-10", navPercent: -2, estimateDate: nil, estimatePercent: nil, now: friday) == nil, "前日净值不参与今日盈亏")
        check(FundQuotePolicy.effectivePercent(navDate: "2026-09-11", navPercent: -2, estimateDate: "2026-09-11", estimatePercent: 1.5, now: friday) == .init(percent: 1.5, isEstimate: true), "当日估值优先于当日净值")
        check(FundQuotePolicy.effectivePercent(navDate: "2026-09-11", navPercent: -2, estimateDate: "2026-09-10", estimatePercent: 1.5, now: friday) == .init(percent: -2, isEstimate: false), "旧估值回退到当日净值")
        check(FundQuotePolicy.effectivePercent(navDate: "2026-09-11", navPercent: -2, estimateDate: nil, estimatePercent: nil, now: saturday) == nil, "周末不把周五涨跌当作今日涨跌")
        check(FundQuotePolicy.effectivePercent(navDate: "2026-09-11", navPercent: .nan, estimateDate: nil, estimatePercent: nil, now: friday) == nil, "异常百分比不参与统计")
    }

    static func syncPayloadTests() {
        print("iCloud 同步载荷:")
        let holdings = [Holding(code: "161725", name: "招商中证白酒A", amount: 10000, cost: 11820)]
        var payload = SyncPayload.build(from: holdings)
        payload.settings[SettingsKey.alertEnabled] = .bool(true)
        payload.updatedAt = Date(timeIntervalSince1970: 1_760_000_000)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let data = try encoder.encode(payload)
            let restored = try decoder.decode(SyncPayload.self, from: data)
            check(restored.holdings == holdings, "持仓往返一致")
            check(restored.updatedAt == payload.updatedAt, "时间戳往返一致")
            check(restored.settings[SettingsKey.alertEnabled] == .bool(true), "布尔设置类型保持")
            check(restored.settings[SettingsKey.menuBarCodes] == .string("1.000001"), "默认设置键值")
        } catch {
            check(false, "同步载荷编解码异常:\(error)")
        }
    }

    static func refreshPolicyTests() {
        print("刷新策略:")
        check(RefreshPolicy.isScheduled(interval: 60), "60s 为自动模式")
        check(RefreshPolicy.isScheduled(interval: 300), "300s 为自动模式")
        check(!RefreshPolicy.isScheduled(interval: 0), "0 为仅手动刷新")
        check(RefreshPolicy.autoRefreshAllowed(isWeekend: false), "工作日允许自动刷新")
        check(!RefreshPolicy.autoRefreshAllowed(isWeekend: true), "周末跳过自动刷新")
        checkEqual(RefreshPolicy.backoffMultiplier(consecutiveFailures: 0), 1, accuracy: 0.001, "无失败 1x")
        checkEqual(RefreshPolicy.backoffMultiplier(consecutiveFailures: 2), 2, accuracy: 0.001, "失败 2 次 2x")
        checkEqual(RefreshPolicy.backoffMultiplier(consecutiveFailures: 9), 4, accuracy: 0.001, "退避 4x 封顶")
        let next = RefreshPolicy.nextAllowedAt(lastInterval: 60, consecutiveFailures: 2, from: Date(timeIntervalSince1970: 1_000_000))
        checkEqual(next.timeIntervalSince1970, 1_000_120, accuracy: 0.001, "退避间隔 = 60s × 2")
        let nextFloor = RefreshPolicy.nextAllowedAt(lastInterval: 0, consecutiveFailures: 1, from: Date(timeIntervalSince1970: 1_000_000))
        checkEqual(nextFloor.timeIntervalSince1970, 1_000_030, accuracy: 0.001, "手动模式失败退避按 30s 下限")
    }

    static func syncLoopGuardTests() {
        print("同步防乒乓与熔断:")
        let h = [Holding(code: "161725", name: "白酒", amount: 10000, cost: nil)]
        var a = SyncPayload.build(from: h)
        a.updatedAt = Date(timeIntervalSince1970: 1_000_000)
        var b = SyncPayload.build(from: h)
        b.updatedAt = Date(timeIntervalSince1970: 2_000_000)
        check(a == b, "内容相同则等值(忽略时间戳)→ 不回推,防乒乓")
        var c = SyncPayload.build(from: h)
        c.updatedAt = a.updatedAt
        c.settings[SettingsKey.refreshInterval] = .double(300)
        check(a != c, "设置不同则不等值 → 正常推送")

        let now = Date()
        check(!RefreshPolicy.eastMoneyInCooldown(consecutiveFailures: 0, lastFailureAt: now, now: now), "无失败不熔断")
        check(!RefreshPolicy.eastMoneyInCooldown(consecutiveFailures: 1, lastFailureAt: now, now: now), "仅失败 1 次不熔断")
        check(RefreshPolicy.eastMoneyInCooldown(consecutiveFailures: 2, lastFailureAt: now, now: now), "连续失败 2 次进入冷却")
        check(!RefreshPolicy.eastMoneyInCooldown(consecutiveFailures: 2, lastFailureAt: now.addingTimeInterval(-301), now: now), "冷却期(5 分钟)过后重新试探")
    }

    static func syncConflictTests() {
        print("iCloud 同步冲突判定:")
        let original = SyncPayload.build(from: [Holding(code: "A", name: "A", amount: 1000, cost: nil)])
        var local = original
        local.holdings[0].amount = 1200
        var remote = original
        remote.holdings[0].amount = 1300
        remote.updatedAt = original.updatedAt.addingTimeInterval(1)
        check(SyncConflictPolicy.decide(local: original, remote: original, baseline: original) == .unchanged, "双方内容相同无需写回")
        check(SyncConflictPolicy.decide(local: local, remote: original, baseline: original) == .pushLocal, "仅本机修改可推送")
        check(SyncConflictPolicy.decide(local: original, remote: remote, baseline: original) == .applyRemote, "仅云端修改可拉取")
        check(SyncConflictPolicy.decide(local: local, remote: remote, baseline: original) == .conflict, "双方修改时保留两份并暂停")
        check(SyncConflictPolicy.decide(local: local, remote: original, baseline: nil) == .conflict, "旧版首次同步有差异时暂停并保留两份")
        check(SyncConflictPolicy.decide(local: local, remote: nil, baseline: nil) == .pushLocal, "全新安装可创建云端文件")
        check(SyncConflictPolicy.decide(local: local, remote: nil, baseline: original) == .conflict, "已同步文件消失时不盲目重建")
        var rolledBack = remote
        rolledBack.updatedAt = original.updatedAt.addingTimeInterval(-1)
        check(SyncConflictPolicy.decide(local: original, remote: rolledBack, baseline: original) == .conflict, "云端旧时间戳变化需人工确认")
    }

    static func runAll() {
        holdingMathTests()
        eastmoneyDecodeTests()
        danjuanDecodeTests()
        indexDefTests()
        tencentParseTests()
        tencentDateTests()
        tradingDayTests()
        menuBarRendererTests()
        sparklineAndStageTests()
        searchAndEstimateTests()
        fundQuoteFreshnessTests()
        syncPayloadTests()
        refreshPolicyTests()
        syncLoopGuardTests()
        syncConflictTests()
        alertTests()
        holdingSortingTests()
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
