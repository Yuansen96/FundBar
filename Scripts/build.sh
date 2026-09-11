#!/bin/bash
# 开发构建(swift build,支持增量编译)
#
# 工具链自动检测:优先使用 ~/tools/swift-6.0.3 开源工具链(当系统 CLT 的
# SwiftPM 损坏/SDK 不匹配时),否则回落到系统 swift。
set -euo pipefail
cd "$(dirname "$0")/.."

OSS_TOOLCHAIN="$HOME/tools/swift-6.0.3/usr/bin"
if [ -x "$OSS_TOOLCHAIN/swiftc" ]; then
    export PATH="$OSS_TOOLCHAIN:$PATH"
fi
export SDKROOT="${SDKROOT:-$(xcrun -sdk macosx --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)}"

swift build
echo "构建完成:.build/debug/FundBar(直接运行即可进入菜单栏)"
