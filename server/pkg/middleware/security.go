package middleware

import (
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

// SecurityHeaders 安全响应头中间件
func SecurityHeaders() gin.HandlerFunc {
	return func(c *gin.Context) {
		// 防止点击劫持
		c.Header("X-Frame-Options", "DENY")
		// 防止 MIME 类型嗅探
		c.Header("X-Content-Type-Options", "nosniff")
		// 启用 XSS 过滤
		c.Header("X-XSS-Protection", "1; mode=block")
		// 严格传输安全（HTTPS）
		c.Header("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
		// 防止 referrer 泄露
		c.Header("Referrer-Policy", "strict-origin-when-cross-origin")
		// 限制 GPU 访问
		c.Header("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
		// CSP 基础策略
		c.Header("Content-Security-Policy", "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:")

		c.Next()
	}
}

// RequestSizeLimit 请求体大小限制中间件
func RequestSizeLimit(maxBytes int64) gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, maxBytes)
		c.Next()
	}
}

// RateLimiter 简单的内存速率限制器
type RateLimiter struct {
	visitors map[string]*visitor
	mu       sync.RWMutex
	rate     int           // 每窗口允许的请求数
	window   time.Duration // 时间窗口
}

type visitor struct {
	count    int
	lastSeen time.Time
}

// NewRateLimiter 创建速率限制器
func NewRateLimiter(rate int, window time.Duration) *RateLimiter {
	rl := &RateLimiter{
		visitors: make(map[string]*visitor),
		rate:     rate,
		window:   window,
	}
	// 定期清理过期记录
	go func() {
		for {
			time.Sleep(time.Minute)
			rl.cleanup()
		}
	}()
	return rl
}

// RateLimit 速率限制中间件
func (rl *RateLimiter) RateLimit() gin.HandlerFunc {
	return func(c *gin.Context) {
		ip := c.ClientIP()

		rl.mu.Lock()
		v, exists := rl.visitors[ip]
		if !exists || time.Since(v.lastSeen) > rl.window {
			rl.visitors[ip] = &visitor{count: 1, lastSeen: time.Now()}
			rl.mu.Unlock()
			c.Next()
			return
		}

		if v.count >= rl.rate {
			rl.mu.Unlock()
			c.JSON(http.StatusTooManyRequests, gin.H{
				"success": false,
				"error":   "请求过于频繁，请稍后再试",
			})
			c.Abort()
			return
		}

		v.count++
		v.lastSeen = time.Now()
		rl.mu.Unlock()
		c.Next()
	}
}

// cleanup 清理过期的访问记录
func (rl *RateLimiter) cleanup() {
	rl.mu.Lock()
	defer rl.mu.Unlock()
	for ip, v := range rl.visitors {
		if time.Since(v.lastSeen) > rl.window*2 {
			delete(rl.visitors, ip)
		}
	}
}
