# 速签 IPA 构建指南

## 方法一：使用 GitHub Actions（推荐）

由于 iOS 应用只能在 macOS 上编译，推荐使用 GitHub Actions 在云端构建。

### 步骤：

1. **将项目推送到 GitHub**
   ```bash
   cd C:\Users\13266\Desktop\速签
   git init
   git add .
   git commit -m "Initial commit"
   git remote add origin https://github.com/你的用户名/速签.git
   git push -u origin main
   ```

2. **触发构建**
   - 访问你的 GitHub 仓库
   - 点击 "Actions" 选项卡
   - 选择 "Build Unsigned IPA" 工作流
   - 点击 "Run workflow"

3. **下载构建产物**
   - 构建完成后（约 10-15 分钟）
   - 在 Actions 页面点击完成的工作流
   - 在 "Artifacts" 部分下载 `JiSign-unsigned`

4. **上传到服务器**
   ```bash
   scp JiSign-unsigned.ipa root@8.155.23.131:/opt/jisign/ipa/JiSign-unsigned.ipa
   ```

---

## 方法二：在 Mac 上本地构建

如果你有 Mac 电脑，可以直接在本地构建。

### 前置要求：
- macOS 12.0+
- Xcode 16.0+
- Homebrew

### 步骤：

1. **复制项目到 Mac**
   ```bash
   # 在 Mac 上
   scp -r 用户名@Windows电脑IP:C:/Users/13266/Desktop/速签 ~/Desktop/速签
   ```

2. **运行构建脚本**
   ```bash
   cd ~/Desktop/速签
   chmod +x build-ipa.sh
   ./build-ipa.sh
   ```

3. **上传到服务器**
   ```bash
   scp JiSign-unsigned.ipa root@8.155.23.131:/opt/jisign/ipa/
   ```

---

## 方法三：使用云 macOS 服务

如果你没有 Mac，可以使用以下云服务：

### 选项 A：MacStadium
- 访问 https://www.macstadium.com/
- 租用一台 Mac mini
- 按照方法二的步骤构建

### 选项 B：AWS EC2 Mac
- 在 AWS 上启动 Mac 实例
- 按照方法二的步骤构建

### 选项 C：GitHub Codespaces (实验性)
- GitHub Codespaces 支持 macOS runner（需要 Team/Enterprise 计划）

---

## 验证构建结果

构建完成后，IPA 文件应该包含：

```
JiSign-unsigned.ipa
└── Payload/
    └── JiSign.app/
        ├── JiSign (可执行文件)
        ├── Info.plist
        ├── Assets.xcassets/
        └── ...
```

你可以用以下命令验证：
```bash
unzip -l JiSign-unsigned.ipa
```

---

## 常见问题

### Q: 构建时提示 "No signing certificate"?
A: 这是正常的，因为我们禁用了代码签名。确保使用了以下参数：
```
CODE_SIGN_IDENTITY=""
CODE_SIGNING_REQUIRED=NO
CODE_SIGNING_ALLOWED=NO
```

### Q: 构建失败，提示找不到 zsign 包？
A: 确保网络连接正常，XcodeGen 会自动下载依赖包。

### Q: IPA 文件太大？
A: 正常的未签名 IPA 大约 10-20 MB。如果过大，检查是否包含了调试符号。

---

## 下一步

构建并上传 IPA 文件后，运行部署脚本：

```bash
cd C:\Users\13266\Desktop\速签
./deploy.sh
```

然后访问 https://8.155.23.131:8443 测试签名功能。
