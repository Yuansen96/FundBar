#!/bin/bash
# 运行测试:编译测试可执行文件并运行(退出码非 0 表示有失败)。
# 测试不依赖 XCTest,任何工具链(含 Command Line Tools / 开源工具链)均可运行。
set -euo pipefail
cd "$(dirname "$0")/.."

OSS_TOOLCHAIN="$HOME/tools/swift-6.0.3/usr/bin"
if [ -x "$OSS_TOOLCHAIN/swiftc" ]; then
    export PATH="$OSS_TOOLCHAIN:$PATH"
fi
export SDKROOT="${SDKROOT:-$(xcrun -sdk macosx --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)}"

mkdir -p .build
# 共享模块缓存:首次运行需编译系统模块(较慢),之后增量
swiftc -O -parse-as-library -swift-version 5 \
  -module-cache-path .build/module-cache \
  -target arm64-apple-macosx14.0 \
  $(find Sources/FundBar -name '*.swift' ! -name 'FundBarApp.swift') \
  Tests/FundBarTests/TestMain.swift \
  -o .build/FundBarTests

.build/FundBarTests
