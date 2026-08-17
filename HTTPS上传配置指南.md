# HTTPS上传配置指南 - 解决iOS明文HTTP上传问题

**问题**：iOS上传IPA走明文HTTP（`http://39.96.76.211`），不安全
**解决方案**：新增 `upload.susuq.top` HTTPS上传子域

---

## 📋 执行步骤

### 步骤1：添加DNS记录（需手动操作）

在域名管理面板（阿里云/腾讯云等）添加：

| 类型 | 主机记录 | 记录值 | TTL |
|------|---------|--------|-----|
| A | upload | 39.96.76.211 | 10分钟 |

**验证DNS生效**：
```bash
# 等待5-10分钟后测试
nslookup upload.susuq.top
# 应返回 39.96.76.211
```

---

### 步骤2：获取SSL证书（DNS生效后执行）

SSH登录服务器执行：

```bash
# 获取upload.susuq.top的SSL证书
certbot certonly --nginx -d upload.susuq.top --non-interactive --agree-tos --email your-email@example.com

# 验证证书
certbot certificates | grep upload
```

---

### 步骤3：配置Nginx（证书获取后执行）

```bash
# 创建upload子域配置
cat > /etc/nginx/sites-available/upload.susuq.top << 'EOF'
# upload.susuq.top - iOS上传专用
server {
    listen 443 ssl;
    server_name upload.susuq.top;

    ssl_certificate /etc/letsencrypt/live/susuq.top/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/susuq.top/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # 上传文件大小限制（100MB）
    client_max_body_size 100M;

    # 上传接口代理
    location /api/install/upload {
        proxy_pass https://127.0.0.1:8080;
        proxy_ssl_verify off;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # 上传超时设置
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }

    # 其他API请求
    location /api/ {
        proxy_pass https://127.0.0.1:8080;
        proxy_ssl_verify off;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

# 启用配置
ln -sf /etc/nginx/sites-available/upload.susuq.top /etc/nginx/sites-enabled/

# 测试Nginx配置
nginx -t

# 重载Nginx
systemctl reload nginx
```

---

### 步骤4：更新iOS客户端代码

修改文件：`ios/JiSign/Core/Network/APIClient.swift`

**修改前**（第14行）：
```swift
private let directURL = "http://39.96.76.211"
```

**修改后**：
```swift
private let directURL = "https://upload.susuq.top"
```

---

### 步骤5：测试验证

```bash
# 测试HTTPS上传端点
curl -X POST https://upload.susuq.top/api/install/upload \
  -F "file=@test.ipa" \
  -F "bundleID=com.test.app" \
  -F "appName=TestApp"

# 应返回JSON响应，而非连接错误
```

---

## 📁 已准备的文件

- Nginx配置：服务器 `/tmp/upload-nginx.conf`
- 本指南：`HTTPS上传配置指南.md`

---

## ⚠️ 注意事项

1. **DNS传播时间**：添加DNS记录后需等待5-10分钟生效
2. **证书自动续期**：Let's Encrypt证书90天自动续期，无需手动操作
3. **上传限制**：已配置100MB文件大小限制
4. **超时设置**：上传超时300秒，适合大文件传输

---

## 🔧 自动化执行脚本

DNS生效后，可一键执行以下命令完成配置：

```bash
#!/bin/bash
# upload-ssl-setup.sh

echo "=== 获取SSL证书 ==="
certbot certonly --nginx -d upload.susuq.top --non-interactive --agree-tos --email admin@susuq.top

echo "=== 配置Nginx ==="
cp /tmp/upload-nginx.conf /etc/nginx/sites-available/upload.susuq.top
ln -sf /etc/nginx/sites-available/upload.susuq.top /etc/nginx/sites-enabled/

echo "=== 测试并重载Nginx ==="
nginx -t && systemctl reload nginx

echo "=== 验证配置 ==="
curl -I https://upload.susuq.top

echo "✅ 配置完成！"
```

---

## 📞 问题排查

| 问题 | 解决方案 |
|------|---------|
| DNS不解析 | 检查DNS记录是否正确，等待传播 |
| SSL证书错误 | 检查certbot日志：`/var/log/letsencrypt/` |
| 502 Bad Gateway | 检查后端服务是否运行：`docker ps` |
| 上传超时 | 检查Nginx超时配置和后端处理时间 |

---

**配置完成后**，iOS应用将通过HTTPS安全上传IPA文件，解决明文HTTP的安全隐患。
