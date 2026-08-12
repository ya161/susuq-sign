#!/bin/bash
# 速签 IPA 构建脚本 (需要在 macOS 上运行)
# Usage: ./build-ipa.sh

set -e

echo "=== 速签 IPA 构建脚本 ==="
echo ""

# 检查是否在 macOS 上运行
if [[ "$(uname)" != "Darwin" ]]; then
    echo "❌ 错误：此脚本只能在 macOS 上运行"
    exit 1
fi

# 检查 Xcode 是否安装
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ 错误：未找到 xcodebuild，请安装 Xcode"
    exit 1
fi

# 检查 XcodeGen 是否安装
if ! command -v xcodegen &> /dev/null; then
    echo "📦 安装 XcodeGen..."
    brew install xcodegen
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_DIR="$SCRIPT_DIR/ios"
BUILD_DIR="$SCRIPT_DIR/build"
OUTPUT_DIR="$SCRIPT_DIR"

echo "[1/4] 生成 Xcode 项目..."
cd "$IOS_DIR"
xcodegen generate

echo "[2/4] 编译项目 (无代码签名)..."
xcodebuild -project JiSign.xcodeproj \
    -scheme JiSign \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$BUILD_DIR" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    ENABLE_BITCODE=NO \
    clean build

echo "[3/4] 创建 IPA 结构..."
mkdir -p "$BUILD_DIR/ipa/Payload"
cp -r "$BUILD_DIR/Build/Products/Release-iphoneos/JiSign.app" "$BUILD_DIR/ipa/Payload/"

cd "$BUILD_DIR/ipa"
zip -r "$OUTPUT_DIR/JiSign-unsigned.ipa" Payload/

echo "[4/4] 清理临时文件..."
rm -rf "$BUILD_DIR"

echo ""
echo "✅ 构建完成！"
echo "📁 IPA 文件位置: $OUTPUT_DIR/JiSign-unsigned.ipa"
echo ""
echo "下一步："
echo "  scp JiSign-unsigned.ipa root@8.155.23.131:/opt/jisign/ipa/"
