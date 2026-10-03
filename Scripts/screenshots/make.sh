#!/bin/bash
# 使用固定示例数据生成 README 截图；不访问网络或修改持仓。
set -euo pipefail
cd "$(dirname "$0")/../.."

OSS_TOOLCHAIN="$HOME/tools/swift-6.0.3/usr/bin"
if [ -x "$OSS_TOOLCHAIN/swiftc" ]; then
    export PATH="$OSS_TOOLCHAIN:$PATH"
fi
export SDKROOT="${SDKROOT:-$(xcrun -sdk macosx --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)}"

mkdir -p .build
swiftc -swift-version 5 -module-cache-path .build/module-cache -target arm64-apple-macosx14.0 \
  Sources/FundBar/Models.swift Sources/FundBar/Services/*.swift \
  Sources/FundBar/Views/*.swift Sources/FundBar/Support/*.swift \
  Scripts/screenshots/main.swift -o .build/make-screenshots
.build/make-screenshots "${1:-docs}"
