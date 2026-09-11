// swift-tools-version:6.0
import PackageDescription

// 说明:测试不使用 XCTest(部分环境无完整 Xcode),请运行 Scripts/test.sh
let package = Package(
    name: "FundBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "FundBar",
            path: "Sources/FundBar",
            // 规避 Swift 6.0.3 IRGen 对属性包装器调试类型 round-trip 的断言崩溃
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-disable-round-trip-debug-types"])
            ]
        )
    ],
    // 保持 Swift 5 语言模式,兼容各工具链
    swiftLanguageVersions: [.v5]
)
