# 极签 - 待完成任务清单

**最近更新**: 2026-04-17（本轮修复 17 项后重写）

---

## 一、✅ 本轮已修复（17 项）

### 🔴 必修（11 项已完成 + 1 项待运维）

| # | 项 | 代码改动位置 |
|---|----|------------|
| 1 | 支付回调校验 AppId/SellerId | `payment.go:99-139` + `main.go` 加 `ALIPAY_SELLER_ID` |
| 2 | `debugCode` 按 `APP_ENV` 而非 SMSClient nil | `auth.go:SendSMSCode` + 新增 `AppEnv` 字段 |
| 3 | JWT 弱密钥 prod 拒绝启动 | `main.go` 新增 `APP_ENV` 判断，非 dev 下 `log.Fatal` |
| 4 | UDID 链路 HMAC 签名 + 权限 | `udid.go` 全面重写；加 `/api/udid/sign` 认证接口；`device_repo.go` 禁止跨用户改绑 |
| 5 | iOS token 迁移 Keychain | 新增 `Core/Storage/KeychainHelper.swift`；`APIClient` 读写 Keychain |
| 6 | Web 支付持久化 orderNo | `purchase/page.tsx` 用 `localStorage` 记 pending orderNo；页面加载时恢复 |
| 7 | 自签临时目录隔离 | `selfsign.go:saveCertFiles` 改 `os.MkdirTemp` + defer `RemoveAll` |
| 8 | 自签 ID UUID + 绑用户 | `selfsign.go` 所有 session_id / installID 改 UUID；加 `ownerUserID` 字段 |
| 9 | GenerateCert 用 order.UDID + 幂等 | `cert_service.go:generateCertLocked` 只信 order；查已有 cert 幂等返回 |
| 11 | `/api/install/upload` 加认证 | `main.go` 路由从公开组移到 `auth` 组 |
| 12 | 自签去掉 ipa_path | `selfsign.go:SignIPA` 移除请求参数，固定指向 `JiSign-unsigned.ipa` |

**#10（iOS 上传走明文 HTTP）** — 🟡 **待运维决策**
- 需要服务器侧新增一个带有效证书的上传专用 HTTPS 子域（或放弃 Cloudflare 100MB 限制的直连方案）
- iOS 侧 `APIClient.directURL` 改指向新域即可
- 当前保持现状

### 🟡 建议（5 项全完成）

| # | 项 | 代码改动位置 |
|---|---|------------|
| 13 | Web 价格从后端取 | 新增 `GET /api/cert/price`；`purchase/page.tsx` 从后端拉 |
| 14 | 验证码 + 限流改 Redis | 新增 `internal/cache/redis.go`；`auth.go` 用 `VerifyCodeStore` 接口；Redis 不可用时回退进程内 |
| 15 | TRADE_CLOSED 检查写库错误 | `payment.go` 失败返回 `fail` 让支付宝重试 |
| 16 | iOS 购买页轮询改造 | `CertStoreView.PurchaseView` 持久化 pending orderNo；改查 `getOrders` 状态；`onDisappear` 清 Timer/Task；`onChange(scenePhase)` 后台回前台自动恢复 |
| 17 | iOS 启动校验 JWT exp + 401 拦截 | `KeychainHelper.swift:JWTInspector`；`APIClient.send()` 统一 401 处理 + `NotificationCenter` 广播；`JiSignApp` 监听退登 |

### 🟢 顺手清理

| # | 项 | 改动 |
|---|---|------|
| 19 | CORS 白名单配置化 | 从 `CORS_ALLOWED_ORIGINS` 环境变量读（默认含 `www.susuq.top`） |
| 20 | 删除 payment.go 占位 goroutine | 改为真正异步调用 `GenerateCertForOrder`（按订单幂等） |
| — | 删除 `main.go` 里空的 `init()` | 无用的 `_ = time.Now().UnixNano()` |
| — | install.go 各 token 改 UUID | `upload_`、`local_`、`sign_` 前缀全改随机 |

---

## 二、环境变量变更

对比 `server/.env` 现状，只需**追加 1 行**：

```bash
# 必填（否则按 dev 模式跑：会向客户端回包 debugCode，JWT 弱密钥不会被拦）
APP_ENV=prod
```

现有变量保持原样即可：

| 变量 | 你的现状 | 状态 |
|------|--------|------|
| `ALIPAY_APP_ID` | `<你的支付宝APP_ID>` | ✅ 支付回调身份校验自动生效 |
| `ALIPAY_SELLER_ID` | 未设置 | ✅ 可不填（同商户下 SELLER_ID 等价于 APP_ID 校验，加不加防护一样） |
| `JWT_SECRET` | `<已移除·自行设置>`（长度 18） | ✅ 通过新的强度检查 |
| `REDIS_URL` | `redis://127.0.0.1:6379/0` | ✅ 代码已兼容标准 URL 格式 |
| `CORS_ALLOWED_ORIGINS` | 未设置 | ✅ 默认含 `susuq.top`、`www.susuq.top`、`api.susuq.top` |
| 其他 `ALIPAY_*`、`ALIYUN_*`、`DATABASE_URL`、`BASE_URL` 等 | 齐全 | ✅ 无改动 |

**安全说明**：支付回调身份校验已经因为 `ALIPAY_APP_ID` 自动生效，能挡掉其他商户伪造的通知。如与其他项目共用同一支付宝 APP_ID，理论上存在订单号碰撞风险，但只要订单号格式不同（本项目是 `JS` + UUID 前 16 位），实际 `FindByOrderNo` 就会直接拒。

---

## 三、⚠️ 部署前注意事项

1. **Redis 必须跑起来** — 生产环境连不上会直接 `log.Fatal`（dev 回退内存）
2. **DB migration 可能需要** — `device_repo.Save` 的 `ON CONFLICT` 带 `WHERE` 子句，Postgres 14+ 支持，请确认生产 DB 版本
3. **客户端改动需要发版**：
   - iOS：`KeychainHelper.swift` 新文件 + `APIClient` 大改（token 搬家 + sig + 401 处理）
   - Web：`purchase/page.tsx` 逻辑 + `lib/api.ts` 新增 `getCertPrice`、`getUdidSign`
4. **支付宝 SELLER_ID 必填** — 不然 prod 回调会失败（空字符串会走条件判断放行，但强烈建议配置）
5. **首次部署的用户**：pending orderNo 流程对老用户无影响（用户无 `localStorage` 条目自然走正常流程）

---

## 四、🟢 暂未处理的可选项（留着以后再看）

### #18 `p12_password` 在 API body 冗余暴露
- 位置：`cert.go:DownloadCert` 和 `cert_service.go:GenerateCertResult`
- 影响：密码 "1" 是内测侠固定默认，客户端已硬编码，暴露不是直接安全问题
- 修法：服务端移除 body 里的 `p12_password`，客户端改用常量

### #21 Git 仓库首次提交前核对
- 仓库还没有任何 commit
- 首次推送前：确认 `server/.env` 和 `server/certs/alipay/app_private_key.pem` 确实被 `.gitignore` 挡住
- 若之前本地曾手工暴露过这些，建议轮换：
  - 支付宝应用私钥
  - 阿里云 AK
  - JWT secret

### #10 iOS 明文上传（前文已提）
- 等后端 HTTPS 子域决策

---

## 五、✅ 上一轮已核验修复（保留记录）

旧 TODO 中原 9 个严重问题 + 5 个真机测试项，全部核验已修复（见上版 TODO 的"✅ 已确认修复"表）。

---

## 六、本轮涉及代码变更清单

### Server（Go）
- `cmd/server/main.go` — wiring: APP_ENV 判断、CORS 配置化、Redis 初始化、Alipay SELLER_ID、UDID StateKey、路由调整
- `internal/cache/redis.go` — **新建**：`VerifyCodeStore` 接口 + Redis/内存实现
- `internal/handler/auth.go` — 改用 `VerifyCodeStore`；debugCode 按 APP_ENV
- `internal/handler/payment.go` — AppId/SellerId 校验 + TRADE_CLOSED 错误检查 + 异步生成证书
- `internal/handler/udid.go` — 全面重写：HMAC sig 生成/校验、`/api/udid/sign` 接口、匿名/登录分流
- `internal/handler/selfsign.go` — 临时目录隔离、ID UUID、session 绑 user_id、移除 ipa_path
- `internal/handler/install.go` — 所有 token 改 UUID、临时目录隔离
- `internal/handler/cert.go` — 新增 `Price()` 公开接口
- `internal/repository/device_repo.go` — `Save` 冲突时禁止跨用户改绑
- `internal/service/cert_service.go` — 重构 `GenerateCert` + 新增 `GenerateCertForOrder`；幂等；`GetPrice` 暴露价格

### Web
- `lib/api.ts` — 新增 `getUdidSign`、`getCertPrice`；`getUdidConfigUrl`/`checkUdid` 支持 sig
- `app/purchase/page.tsx` — 持久化 pending orderNo、从后端拉价格、用 sig 调 UDID 接口、`startOrderPolling` 先查订单状态再拉证书

### iOS
- `Core/Storage/KeychainHelper.swift` — **新建**：Keychain 读写 + `JWTInspector` 解析 exp
- `Core/Network/APIClient.swift` — token 搬 Keychain；401 统一拦截；`getUdidSign`；`udidConfigURL`；`isAuthenticated` 验证 exp
- `App/JiSignApp.swift` — 监听 `.jiSignUnauthorized` 自动退登；登录成功预取 udid sig
- `Features/Profile/LoginView.swift` — 登录成功预取 udid sig
- `Features/CertStore/CertStoreView.swift` — 持久化 pending orderNo；改用订单状态轮询；`onDisappear` 清理；scenePhase 自动恢复

