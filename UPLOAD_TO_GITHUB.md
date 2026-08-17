# 上传代码到 GitHub

由于网络问题，无法通过 Git 推送。请按以下步骤手动上传：

## 方法一：使用 GitHub 网页上传（推荐）

1. **打开仓库页面**：
   https://github.com/ya161/susuq-sign

2. **点击 "uploading an existing file"**

3. **拖拽以下文件/文件夹到页面**：
   - `web/` 文件夹（前端代码）
   - `server/` 文件夹（后端代码，不包含二进制文件）
   - `ios/` 文件夹（iOS 项目）
   - `docker-compose.yml`
   - `.github/` 文件夹（如果存在）
   - `.gitignore`
   - `README.md`（如果有）

4. **点击 "Commit changes"**

## 方法二：使用 GitHub Desktop

1. 下载安装 GitHub Desktop：https://desktop.github.com/
2. 登录你的 GitHub 账户
3. 点击 "Add an Existing Repository from your Hard Drive"
4. 选择 `C:\Users\13266\Desktop\速签` 文件夹
5. 点击 "Publish repository"

## 方法三：创建 Personal Access Token（带 workflow 权限）

1. 访问：https://github.com/settings/tokens
2. 点击 "Generate new token (classic)"
3. 填写：
   - Note: `susuq-sign`
   - Expiration: 90 days
   - 勾选：`repo` 和 `workflow`
4. 点击 "Generate token"
5. 复制新 token 并告诉我

---

上传完成后，GitHub Actions 会自动构建 IPA 文件。
