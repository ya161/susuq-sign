package main

import (
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
	"github.com/haifeng/jisign-server/internal/cache"
	"github.com/haifeng/jisign-server/internal/handler"
	"github.com/haifeng/jisign-server/internal/neicexia"
	"github.com/haifeng/jisign-server/internal/repository"
	"github.com/haifeng/jisign-server/internal/service"
	"github.com/haifeng/jisign-server/internal/payment"
	"github.com/haifeng/jisign-server/internal/sms"
	"github.com/haifeng/jisign-server/internal/yiqian"
	"github.com/haifeng/jisign-server/pkg/middleware"
)

// APP_ENV 全局环境标识（dev / prod）
// 非 dev 环境会启用严格的安全检查（拒绝弱 JWT、不返回 debugCode 等）
var appEnv = "dev"

func main() {
	// 加载 .env 文件
	if err := godotenv.Load(); err != nil {
		log.Println("未找到 .env 文件，使用系统环境变量")
	}

	// 配置
	appEnv = getEnv("APP_ENV", "dev")
	isProd := appEnv != "dev"
	port := getEnv("PORT", "8080")
	baseURL := getEnv("BASE_URL", "https://api.susuq.top")
	neicexiaToken := getEnv("NEICEXIA_TOKEN", "")
	databaseURL := getEnv("DATABASE_URL", "")
	jwtSecret := getEnv("JWT_SECRET", "jisign-default-secret-change-me")

	if neicexiaToken == "" {
		log.Println("警告: NEICEXIA_TOKEN 未设置，证书相关功能不可用")
	}

	// JWT Secret 强度检查：生产环境拒绝默认值或弱密钥
	if jwtSecret == "jisign-default-secret-change-me" || len(jwtSecret) < 16 {
		if isProd {
			log.Fatal("❌ JWT_SECRET 使用默认值或长度不足 16 位，生产环境拒绝启动")
		}
		log.Println("⚠️  警告: JWT_SECRET 使用默认值或长度不足 16 位（dev 模式允许）")
	}

	// 设置 JWT 密钥
	middleware.JWTSecret = []byte(jwtSecret)

	// 初始化数据库
	var db_initialized bool
	if databaseURL != "" {
		db, err := repository.InitDB(databaseURL)
		if err != nil {
			log.Printf("警告: 数据库连接失败: %v，部分功能不可用", err)
		} else {
			defer db.Close()
			db_initialized = true
			log.Println("数据库连接成功")
		}
	} else {
		log.Println("警告: DATABASE_URL 未设置，数据库功能不可用")
	}

	// 初始化内测侠客户端
	nxClient := neicexia.NewClient(neicexiaToken)

	// 初始化仓库和服务（需要数据库）
	var (
		userRepo   *repository.UserRepo
		deviceRepo *repository.DeviceRepo
		certRepo   *repository.CertRepo
		orderRepo  *repository.OrderRepo
		certSvc    *service.CertService
	)

	if db_initialized {
		userRepo = repository.NewUserRepo(repository.DB)
		deviceRepo = repository.NewDeviceRepo(repository.DB)
		certRepo = repository.NewCertRepo(repository.DB)
		orderRepo = repository.NewOrderRepo(repository.DB)
		certSvc = service.NewCertService(certRepo, orderRepo, deviceRepo, nxClient)

		// 启动证书有效性定时检查
		certSvc.StartCertChecker()
	}

	// 初始化验证码存储（Redis 优先；不可用时回退进程内兜底）
	// 优先读 REDIS_URL（标准 URL 格式），否则用 REDIS_ADDR + 密码 + DB 组装
	var (
		verifyStore cache.VerifyCodeStore
		redisErr    error
		rs          *cache.RedisStore
	)
	if redisURL := os.Getenv("REDIS_URL"); redisURL != "" {
		rs, redisErr = cache.NewRedisStoreFromURL(redisURL)
	} else {
		redisAddr := getEnv("REDIS_ADDR", "127.0.0.1:6379")
		redisPassword := getEnv("REDIS_PASSWORD", "")
		redisDB, _ := strconv.Atoi(getEnv("REDIS_DB", "0"))
		rs, redisErr = cache.NewRedisStore(redisAddr, redisPassword, redisDB)
	}
	if redisErr != nil {
		if isProd {
			log.Fatalf("❌ 生产环境 Redis 连接失败: %v", redisErr)
		}
		log.Printf("⚠️  Redis 不可用，回退进程内验证码存储: %v", redisErr)
		verifyStore = cache.NewMemoryStore()
	} else {
		verifyStore = rs
	}

	// 初始化阿里云短信客户端
	var smsClient *sms.AliyunSMSClient
	aliyunKeyID := getEnv("ALIYUN_ACCESS_KEY_ID", "")
	aliyunKeySecret := getEnv("ALIYUN_ACCESS_KEY_SECRET", "")
	smsSignName := getEnv("ALIYUN_SMS_SIGN_NAME", "速签")
	smsTemplateCode := getEnv("ALIYUN_SMS_TEMPLATE_CODE", "")

	if aliyunKeyID != "" && aliyunKeySecret != "" && smsTemplateCode != "" {
		smsClient = sms.NewAliyunSMSClient(aliyunKeyID, aliyunKeySecret, smsSignName, smsTemplateCode)
		log.Println("阿里云短信服务已启用")
	} else {
		log.Println("警告: 阿里云短信未配置，使用 Mock 模式（验证码打印到日志）")
	}

	// 初始化支付宝客户端
	var alipayClient *payment.AlipayClient
	alipayAppID := getEnv("ALIPAY_APP_ID", "")
	alipaySellerID := getEnv("ALIPAY_SELLER_ID", "") // 商户 PID（卖家支付宝用户号），用于回调身份校验
	alipayPrivateKeyPath := getEnv("ALIPAY_PRIVATE_KEY_PATH", "")
	alipayAppCertPath := getEnv("ALIPAY_APP_CERT_PATH", "")
	alipayPublicCertPath := getEnv("ALIPAY_PUBLIC_CERT_PATH", "")
	alipayRootCertPath := getEnv("ALIPAY_ROOT_CERT_PATH", "")

	if alipayAppID != "" && alipayPrivateKeyPath != "" {
		var err error
		alipayClient, err = payment.NewAlipayClient(payment.AlipayConfig{
			AppID:                alipayAppID,
			PrivateKeyPath:       alipayPrivateKeyPath,
			AppCertPath:          alipayAppCertPath,
			AlipayPublicCertPath: alipayPublicCertPath,
			AlipayRootCertPath:   alipayRootCertPath,
			NotifyURL:            getEnv("ALIPAY_NOTIFY_URL", baseURL+"/api/pay/alipay/notify"),
			ReturnURL:            getEnv("ALIPAY_RETURN_URL", baseURL+"/api/pay/alipay/return"),
			IsProduction:         getEnv("ALIPAY_IS_PRODUCTION", "false") == "true",
		})
		if err != nil {
			log.Printf("警告: 支付宝客户端初始化失败: %v", err)
		} else {
			log.Println("支付宝支付已启用")
		}
	} else {
		log.Println("警告: 支付宝未配置，支付功能不可用")
	}

	// UDID 回调签名密钥（派生自 JWT Secret，避免单独配置）
	udidSignKey := []byte("udid-state:" + jwtSecret)

	// 初始化 handlers
	udidHandler := &handler.UDIDHandler{
		BaseURL:    baseURL,
		DeviceRepo: deviceRepo,
		StateKey:   udidSignKey,
	}
	authHandler := &handler.AuthHandler{
		UserRepo:   userRepo,
		DeviceRepo: deviceRepo,
		SMSClient:  smsClient,
		AppEnv:     appEnv,
		Store:      verifyStore,
	}
	deviceHandler := &handler.DeviceHandler{DeviceRepo: deviceRepo}
	orderHandler := &handler.OrderHandler{OrderRepo: orderRepo}
	paymentHandler := &handler.PaymentHandler{
		Alipay:           alipayClient,
		OrderRepo:        orderRepo,
		CertService:      certSvc,
		ExpectedAppID:    alipayAppID,
		ExpectedSellerID: alipaySellerID,
	}
	appHandler := &handler.AppHandler{CertRepo: certRepo, DeviceRepo: deviceRepo, BaseURL: baseURL}
	installHandler := &handler.InstallHandler{
		CertRepo:      certRepo,
		DeviceRepo:    deviceRepo,
		BaseURL:       baseURL,
		IPADir:        "/opt/jisign/ipa",
		UnsignedIPA:   "/opt/jisign/ipa/JiSign-unsigned.ipa",
		NeicexiaToken: neicexiaToken,
	}
	certHandler := &handler.CertHandler{CertService: certSvc, CertRepo: certRepo, Neicexia: nxClient, InstallHandler: installHandler}

	// 易签客户端（用于证书下载）
	yiqianToken := getEnv("YIQIAN_TOKEN", "")
	var certDownloadHandler *handler.CertDownloadHandler
	if yiqianToken != "" {
		yiqianClient := yiqian.NewClient(yiqianToken)
		certDownloadHandler = &handler.CertDownloadHandler{YiqianClient: yiqianClient}
		log.Println("易签API已启用")
	} else {
		log.Println("警告: YIQIAN_TOKEN 未设置，证书下载功能不可用")
	}

	// 路由
	r := gin.Default()

	// 安全中间件
	r.Use(middleware.SecurityHeaders())
	r.Use(middleware.RequestSizeLimit(10 << 20)) // 10MB 请求体限制

	// 全局速率限制：每 IP 每分钟 60 次
	limiter := middleware.NewRateLimiter(60, time.Minute)
	r.Use(limiter.RateLimit())

	// CORS 配置
	r.Use(corsMiddleware())

	// 健康检查
	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"status":  "ok",
			"service": "jisign-server",
			"db":      db_initialized,
		})
	})

	// API 路由
	api := r.Group("/api")
	{
		// ========== 公开路由（无需认证）==========

		// 认证
		api.POST("/auth/sms-code", authHandler.SendSMSCode)
		api.POST("/auth/login", authHandler.Login)

		// UDID 收集（iOS 系统直接调用，无法携带 token）
		api.GET("/udid/config", udidHandler.GetMobileConfig)
		api.POST("/udid/callback", udidHandler.UDIDCallback)
		api.GET("/udid/check", udidHandler.CheckUDID)

		// 证书价格（公开查询，Web/iOS 展示用）
		api.GET("/cert/price", certHandler.Price)

		// 支付宝回调（支付宝服务器调用，无法携带 token）
		api.POST("/pay/alipay/notify", paymentHandler.AlipayNotify)
		api.GET("/pay/alipay/return", paymentHandler.AlipayReturn)

		// App 版本检查（公开接口，App 启动时调用）
		api.GET("/app/version", appHandler.VersionInfo)

		// App 安装（itms-services 协议需要公开访问，iOS 会先 HEAD 再 GET）
		api.GET("/install/manifest/:batch_no", installHandler.Manifest)
		api.HEAD("/install/manifest/:batch_no", installHandler.Manifest)
		api.GET("/install/download/:batch_no", installHandler.Download)
		api.HEAD("/install/download/:batch_no", installHandler.Download)

		// 用户证书签名（公开接口，Web 前端调用）
		api.POST("/install/sign-with-cert", installHandler.SignWithCert)

		// 易签证书下载（公开接口，Web 前端调用）
		if certDownloadHandler != nil {
			api.POST("/cert/download-yiqian", certDownloadHandler.DownloadCert)
		}

		// ========== 需认证路由 ==========
		auth := api.Group("")
		auth.Use(middleware.AuthRequired())
		{
			// 证书管理
			auth.POST("/cert/purchase", certHandler.Purchase)
			auth.POST("/cert/generate", certHandler.GenerateCert)
			auth.GET("/cert/list", certHandler.List)
			auth.POST("/cert/check/:id", certHandler.CheckValid)
			auth.POST("/cert/download", certHandler.DownloadCert)

			// 设备管理
			auth.GET("/devices", deviceHandler.List)
			auth.DELETE("/devices/:id", deviceHandler.Delete)

			// 订单管理
			auth.GET("/orders", orderHandler.List)
			auth.GET("/orders/:id", orderHandler.Detail)

			// 支付宝支付（创建支付链接需要登录）
			auth.POST("/pay/alipay/create", paymentHandler.CreatePayment)

			// App 更新（获取安装链接，需要登录）
			auth.POST("/app/update", appHandler.UpdateApp)

			// UDID 签名令牌（登录后先拿一次，用于后续 config/callback/check）
			auth.GET("/udid/sign", udidHandler.GetSign)

			// 远程签名（上传 IPA → 服务端签名 → 安装链接）
			auth.POST("/install/sign", installHandler.RemoteSign)

			// IPA 安装相关上传：认证保护，避免被滥用为公开文件托管
			auth.POST("/install/local-manifest", installHandler.LocalManifest)
			auth.POST("/install/upload", installHandler.UploadSigned)
		}
	}

	// 本地 HTTPS 证书下载（App 动态获取最新证书，无需重新构建）
	r.GET("/api/cert/local-ssl", func(c *gin.Context) {
		c.File("/opt/jisign/certs/local.p12")
	})

	// App 安装落地页
	r.StaticFile("/install", "./website/index.html")
	r.StaticFile("/manifest.plist", "./website/manifest.plist")

	// UDID 获取成功页
	r.StaticFile("/udid/success", "./website/udid-success.html")

	// 静态文件服务（CSS、JS、字体等）
	r.Static("/_next", "./website/_next")

	// SPA 路由：子路径优先匹配静态文件，最后回退到 index.html
	r.NoRoute(func(c *gin.Context) {
		path := c.Request.URL.Path
		// 尝试直接提供静态文件
		filePath := "./website" + path
		if _, err := os.Stat(filePath); err == nil {
			c.File(filePath)
			return
		}
		// 回退到 index.html（SPA 路由）
		c.File("./website/index.html")
	})

	// 首页
	r.GET("/", func(c *gin.Context) {
		c.File("./website/index.html")
	})

	// SSL证书路径
	certFile := getEnv("SSL_CERT_FILE", "/app/certs/server.crt")
	keyFile := getEnv("SSL_KEY_FILE", "/app/certs/server.key")

	// 启动HTTPS服务
	log.Printf("速签服务启动在 :%s (HTTPS)", port)
	if err := r.RunTLS(":"+port, certFile, keyFile); err != nil {
		log.Fatalf("HTTPS启动失败: %v", err)
	}
}

// loadAllowedOrigins 从 CORS_ALLOWED_ORIGINS 读逗号分隔的白名单；缺省时给出合理默认。
func loadAllowedOrigins() map[string]bool {
	raw := getEnv("CORS_ALLOWED_ORIGINS",
		"https://susuq.top,https://www.susuq.top,https://api.susuq.top,http://localhost:3000")
	result := make(map[string]bool)
	for _, o := range strings.Split(raw, ",") {
		o = strings.TrimSpace(o)
		if o != "" {
			result[o] = true
		}
	}
	return result
}

// corsMiddleware CORS 跨域中间件
func corsMiddleware() gin.HandlerFunc {
	allowedOrigins := loadAllowedOrigins()
	log.Printf("CORS 白名单: %v", keysOf(allowedOrigins))
	return func(c *gin.Context) {
		origin := c.GetHeader("Origin")
		if allowedOrigins[origin] {
			c.Header("Access-Control-Allow-Origin", origin)
			c.Header("Vary", "Origin")
		}
		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Origin, Content-Type, Authorization")
		c.Header("Access-Control-Max-Age", "86400")

		if c.Request.Method == http.MethodOptions {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}

		c.Next()
	}
}

func keysOf(m map[string]bool) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	return keys
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
