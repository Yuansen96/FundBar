# FundBar 📈

macOS 菜单栏基金行情小工具 —— SwiftUI 原生实现,零第三方依赖,常驻菜单栏,点开即看大盘、板块与你手上的基金盈亏。

![Platform](https://img.shields.io/badge/platform-macOS%2014+-black)
![Swift](https://img.shields.io/badge/Swift-5.9%20%2F%20SwiftUI-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## 功能

- **菜单栏常驻,平时只是一个小图标**:点击展开面板查看行情;可在设置中切换「图标 + 指数涨跌摘要」(最多 3 个指数)
- **大盘**:A股(上证 / 深成 / 创业板)+ 亚太(恒生 / 日经225 / 韩国KOSPI)+ 美股(道琼斯 / 纳斯达克 / 标普500),共 9 个指数
- **板块**:行业板块涨跌幅双榜(东财 496 个行业板块)
- **我的基金**:输入基金代码 + 持有金额,自动计算**当日盈亏**与**持有收益**(可选填成本金额);支持编辑与删除;数据存本地
- **净值走势**:点开任意基金查看走势图(近1月 / 近3月 / 近1年 / 近5年),Swift Charts 绘制
- **涨跌提醒**:持仓基金当日涨跌幅越过阈值(±1% / ±2% / ±3% / ±5% 可选)时发送系统通知,每只基金每天最多一次
- **双数据源可选**:设置中可选「自动(东财优先,失败切腾讯)/ 仅东财 / 仅腾讯」;面板底部状态点实时反映数据源健康
- **交易日感知**:非交易日(周末)自动展示上一交易日收盘行情,面板顶部明确标注数据日期;腾讯源可解析数据日期修正节假日标注
- **菜单栏彩色摘要**:「图标+涨跌摘要」模式自绘彩色数字,红涨绿跌突破系统单色限制
- **红涨绿跌**国内配色;交易时间内按设置间隔(30秒 / 1分钟 / 5分钟)自动刷新

## 构建

需要 macOS 14+。测试不依赖 XCTest,任何 Swift 工具链均可运行。

```bash
./Scripts/build.sh   # 开发构建(swift build,增量编译)
./Scripts/test.sh    # 运行测试(可执行测试骨架,退出码 0 = 全部通过)
./make-app.sh        # release 构建 + 打包 FundBar.app + ad-hoc 签名
open FundBar.app     # 启动,菜单栏出现 📈 图标
```

> **工具链说明**:脚本会优先使用 `~/tools/swift-6.0.3/usr/bin` 下的开源工具链
> (若存在)。这是为本机 Command Line Tools 损坏的情况准备的 —— CLT 出现
> "SDK is not supported by the compiler" 或 SwiftPM 清单链接失败时,从
> [swift.org](https://www.swift.org/download/) 下载对应版本的 macOS pkg,
> 用 `pkgutil --expand-full xxx.pkg 目录` 免 sudo 解包到 `~/tools/swift-6.0.3`
> 即可。环境健康的机器上脚本会自动回落到系统 `swift`。

## 数据来源与免责声明

行情数据来自以下公开接口,**均为非官方接口,无可用性保证**:

| 数据 | 接口 |
|------|------|
| 全球指数(主源,沪深 / 恒生 / 日经 / KOSPI / 道指 / 纳指 / 标普) | 东方财富 `push2.eastmoney.com/api/qt/ulist.np/get` |
| 全球指数(备用源,A股 / 恒生 / 美股;日经、KOSPI 无免费替代) | 腾讯 `qt.gtimg.cn/q=...`(GBK) |
| 行业板块涨跌榜 | 东方财富 `push2.eastmoney.com/api/qt/clist/get?fs=m:90+t:2` |
| 基金名称 / 最新净值 / 当日涨跌幅 | 蛋卷基金 `danjuanfunds.com/djapi/fund/{code}` |
| 历史净值(走势图) | 蛋卷基金 `danjuanfunds.com/djapi/fund/nav/history/{code}` |

> **网络兼容性**:东财行情域名是 IPv4/IPv6 双栈解析,在 IPv6 出口异常的网络下,
> URLSession 会因连接被断而报 `-1005`,FundBar 会自动重试并降级到腾讯源,
> 面板底部状态点会变为黄色并提示。日经225 与 KOSPI 无可用的免费备用源
> (新浪国际指数数据过期不可信),降级模式下这两项显示"暂不可用"。
> 注:本项目曾调研天天基金 `fundgz` 估值接口,该接口已失效(404),故基金数据统一走蛋卷。
> 数据仅供参考,不构成任何投资建议;本项目仅供学习交流。

## 灵感来源

数据接口选型参考了以下优秀开源项目,感谢:

- [giscafer/leek-fund](https://github.com/giscafer/leek-fund) —— VSCode「韭菜盒子」插件
- [1zilc/fishing-funds](https://github.com/1zilc/fishing-funds) —— Electron 版菜单栏基金应用(本项目的原生 SwiftUI 替代尝试)

## 项目结构

```
Sources/FundBar/
├── FundBarApp.swift        # @main,MenuBarExtra 入口 + 状态项图标
├── Models.swift            # 指数定义、行情模型、持仓与盈亏计算
├── Services/
│   ├── EastmoneyAPI.swift  # 指数行情 + 板块涨跌榜
│   ├── DanjuanAPI.swift    # 基金详情 + 历史净值
│   └── MarketStore.swift   # 全局状态、定时刷新、持仓持久化
├── Views/
│   ├── PanelView.swift     # 主面板(三页签容器 + 页脚刷新)
│   ├── MarketTabView.swift # 大盘(三地区九指数)
│   ├── SectorTabView.swift # 板块双榜
│   ├── FundTabView.swift   # 持仓列表 + 盈亏汇总
│   ├── AddFundPage.swift   # 添加基金
│   ├── FundDetailPage.swift# 基金详情 + 走势图
│   └── SettingsPage.swift  # 设置(菜单栏模式 / 指数 / 刷新间隔)
└── Support/Helpers.swift   # 红涨绿跌配色 + 数字格式化
```

## Roadmap

- [x] 涨跌提醒通知(阈值越过时系统通知)—— 0.2.0
- [x] 持仓金额编辑入口 —— 0.3.0
- [x] 菜单栏彩色数字(NSImage 自绘)—— 0.3.0
- [ ] 盘中估值:免费源现状 —— 天天基金 fundgz 已 404,蛋卷无公开估值接口,
      fundmobapi 为 IPv4/IPv6 双栈域名(与东财同病)且旧参数已失效;待寻找稳定数据源
- [ ] 自绘折线 mini sparkline(大盘行内展示日内走势)

## License

MIT
