package handler

import (
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"regexp"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/haifeng/jisign-server/internal/cache"
	"github.com/haifeng/jisign-server/internal/repository"
	"github.com/haifeng/jisign-server/internal/sms"
	"github.com/haifeng/jisign-server/pkg/middleware"
)

// AuthHandler 用户认证处理
type AuthHandler struct {
	UserRepo   *repository.UserRepo
	DeviceRepo *repository.DeviceRepo
	SMSClient  *sms.AliyunSMSClient  // 阿里云短信客户端（nil 时使用 mock 模式）
	AppEnv     string                // 环境标识（dev / prod）。仅 dev 返回 debugCode
	Store      cache.VerifyCodeStore // 验证码存储（Redis 或进程内兜底）
}

// 手机号正则（中国大陆 11 位）
var phoneRegex = regexp.MustCompile(`^1[3-9]\d{9}$`)

// SendSMSCodeRequest 发送验证码请求
type SendSMSCodeRequest struct {
	Phone string `json:"phone" binding:"required"`
}

// LoginRequest 登录请求
type LoginRequest struct {
	Phone string `json:"phone" binding:"required"`
	Code  string `json:"code" binding:"required"`
}

// SendSMSCode 发送短信验证码
// POST /api/auth/sms-code
func (h *AuthHandler) SendSMSCode(c *gin.Context) {
	var req SendSMSCodeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "参数错误"})
		return
	}

	// 校验手机号格式
	if !phoneRegex.MatchString(req.Phone) {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "手机号格式不正确"})
		return
	}

	// 速率限制：每分钟最多 5 条
	count, err := h.Store.IncrRateLimit(req.Phone, 1*time.Minute)
	if err != nil {
		log.Printf("速率限制读取失败: %v", err)
		// 缓存故障直接放行（避免全站阻塞），但记录告警
	} else if count > 5 {
		c.JSON(http.StatusTooManyRequests, gin.H{
			"success": false,
			"error":   "验证码发送过于频繁，请稍后再试",
		})
		return
	}

	// 生成 6 位验证码
	code := fmt.Sprintf("%06d", rand.Intn(1000000))

	// 存储验证码（5 分钟有效）
	if err := h.Store.SetCode(req.Phone, code, 5*time.Minute); err != nil {
		log.Printf("验证码写入失败: phone=%s, err=%v", req.Phone, err)
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"success": false,
			"error":   "验证码服务暂不可用",
		})
		return
	}

	// 发送短信
	if h.SMSClient != nil {
		if err := h.SMSClient.SendCode(req.Phone, code); err != nil {
			log.Printf("短信发送失败: phone=%s, err=%v", req.Phone, err)
			c.JSON(http.StatusServiceUnavailable, gin.H{
				"success": false,
				"error":   "验证码发送失败，请稍后再试",
			})
			return
		}
		log.Printf("[阿里云短信] 验证码已发送: phone=%s", req.Phone)
	} else {
		// 短信未配置：仅 dev 允许，prod 直接拒绝
		if h.AppEnv != "dev" {
			log.Printf("[FATAL] 短信未配置但非 dev 环境: phone=%s", req.Phone)
			c.JSON(http.StatusServiceUnavailable, gin.H{
				"success": false,
				"error":   "短信服务未配置",
			})
			return
		}
		log.Printf("[Mock 短信] 手机号: %s, 验证码: %s", req.Phone, code)
	}

	response := gin.H{
		"success": true,
		"data":    gin.H{"message": "验证码已发送"},
	}

	// 只有 dev 环境才回包验证码方便调试；prod 绝不返回
	if h.AppEnv == "dev" {
		response["data"] = gin.H{
			"message":   "验证码已发送",
			"debugCode": code,
		}
	}

	c.JSON(http.StatusOK, response)
}

// Login 手机号+验证码登录
// POST /api/auth/login
func (h *AuthHandler) Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "参数错误"})
		return
	}

	// 校验手机号格式
	if !phoneRegex.MatchString(req.Phone) {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "手机号格式不正确"})
		return
	}

	// 验证验证码（从 Redis 或内存兜底读）
	storedCode, err := h.Store.GetCode(req.Phone)
	if err != nil {
		log.Printf("读取验证码失败: %v", err)
		c.JSON(http.StatusServiceUnavailable, gin.H{"success": false, "error": "验证码服务暂不可用"})
		return
	}

	if storedCode == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "请先获取验证码"})
		return
	}
	if storedCode != req.Code {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "验证码错误"})
		return
	}

	// 验证通过，清除验证码（一次性使用）
	if err := h.Store.DeleteCode(req.Phone); err != nil {
		log.Printf("清理验证码失败: %v", err)
	}

	// 查找或创建用户
	user, err := h.UserRepo.FindByPhone(req.Phone)
	if err != nil {
		log.Printf("查询用户失败: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "服务器内部错误"})
		return
	}

	if user == nil {
		// 新用户，自动注册
		user, err = h.UserRepo.Create(req.Phone)
		if err != nil {
			log.Printf("创建用户失败: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "注册失败"})
			return
		}
		log.Printf("新用户注册: phone=%s, id=%d", user.Phone, user.ID)
	}

	// 迁移匿名设备：将之前 UDID 匿名暂存的设备绑定到当前用户
	if h.DeviceRepo != nil {
		if count, err := h.DeviceRepo.MigratePending(user.ID); err != nil {
			log.Printf("迁移匿名设备失败: %v", err)
		} else if count > 0 {
			log.Printf("已迁移 %d 个匿名设备到用户 %d", count, user.ID)
		}
	}

	// 生成 JWT token
	token, err := middleware.GenerateToken(user.ID, user.Phone)
	if err != nil {
		log.Printf("生成 token 失败: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "登录失败"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data": gin.H{
			"token": token,
			"user":  user,
		},
	})
}
