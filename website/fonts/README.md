# 本地字体说明

由于 Google Fonts 在国内访问较慢，建议使用本地字体。

## 方案一：使用本地字体（推荐）

1. 下载 Geist 字体文件到此目录
2. 在 layout.tsx 中使用 `next/font/local` 替代 `next/font/google`

## 方案二：使用国内 CDN

修改 layout.tsx 中的字体加载方式为国内 CDN 源。
