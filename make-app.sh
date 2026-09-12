#!/bin/bash
# 打包 FundBar.app:release 构建 + 手工组装 bundle(LSUIElement 菜单栏应用)
set -euo pipefail
cd "$(dirname "$0")"

OSS_TOOLCHAIN="$HOME/tools/swift-6.0.3/usr/bin"
if [ -x "$OSS_TOOLCHAIN/swiftc" ]; then
    export PATH="$OSS_TOOLCHAIN:$PATH"
fi
export SDKROOT="${SDKROOT:-$(xcrun -sdk macosx --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)}"

APP_NAME="FundBar"
APP_DIR="$APP_NAME.app"

swift build -c release
BINARY=".build/arm64-apple-macosx/release/$APP_NAME"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BINARY" "$APP_DIR/Contents/MacOS/$APP_NAME"

# 生成应用图标(纯 AppKit 离屏渲染,无外部依赖)
if swiftc -O Scripts/make-icon.swift -o .build/make-icon 2>/dev/null; then
    .build/make-icon "$APP_DIR/Contents/Resources/AppIcon.png"
fi

cat > "$APP_DIR/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>FundBar</string>
    <key>CFBundleIdentifier</key><string>com.gaochenjie.fundbar</string>
    <key>CFBundleName</key><string>FundBar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.6.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleIconFile</key><string>AppIcon</string>
</dict>
</plist>
EOF

# ad-hoc 签名,Apple Silicon 上未签名二进制无法运行
codesign --force --sign - "$APP_DIR"

echo "打包完成:$APP_DIR(运行 open $APP_DIR 启动)"
