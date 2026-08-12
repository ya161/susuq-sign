package handler

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"io"
	"log"
	"net/http"
	"net/url"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/haifeng/jisign-server/internal/model"
	"github.com/haifeng/jisign-server/internal/repository"
	"github.com/haifeng/jisign-server/pkg/udid"
)

// allowedRedirectHosts UDID 回调允许的跳转域名（防 open redirect）
var allowedRedirectHosts = map[string]bool{
	"susuq.top":     true,
	"www.susuq.top": true,
}

// sanitizeRedirect 校验 redirect URL 是否在白名单内，通过则返回 raw，否则返回空串
func sanitizeRedirect(raw string) string {
	if raw == "" {
		return ""
	}
	u, err := url.Parse(raw)
	if err != nil {
		return ""
	}
	if u.Scheme != "https" && u.Scheme != "http" {
		return ""
	}
	if !allowedRedirectHosts[u.Hostname()] {
		return ""
	}
	return raw
}

type UDIDHandler struct {
	BaseURL    string
	DeviceRepo *repository.DeviceRepo
	StateKey   []byte // HMAC 签名密钥，用于给 user_id 绑定的回调加签
}

// signUserID 生成 user_id 的 HMAC 签名（短令牌），仅登录用户才签
func (h *UDIDHandler) signUserID(userID string) string {
	if userID == "" || userID == "0" {
		return ""
	}
	mac := hmac.New(sha256.New, h.StateKey)
	mac.Write([]byte("udid:" + userID))
	return hex.EncodeToString(mac.Sum(nil))[:32]
}

// verifySig 校验 user_id 对应的签名；user_id=0 视为匿名通过
func (h *UDIDHandler) verifySig(userID, sig string) bool {
	if userID == "" || userID == "0" {
		return true
	}
	expected := h.signUserID(userID)
	return hmac.Equal([]byte(expected), []byte(sig))
}

// GetSign 登录用户获取 UDID 签名令牌（供后续 config/check/callback 使用）
// GET /api/udid/sign （需 JWT 认证）
func (h *UDIDHandler) GetSign(c *gin.Context) {
	userID := c.GetInt64("user_id")
	if userID <= 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "未登录"})
		return
	}
	uid := strconv.FormatInt(userID, 10)
	sig := h.signUserID(uid)
	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data": gin.H{
			"sig":        sig,
			"config_url": h.BaseURL + "/api/udid/config?user_id=" + uid + "&sig=" + sig,
		},
	})
}

// GetMobileConfig 返回 UDID 收集描述文件
// GET /api/udid/config?user_id=xxx&sig=xxx
// 登录用户必须带 sig；自签匿名场景使用 user_id=0，无需 sig
func (h *UDIDHandler) GetMobileConfig(c *gin.Context) {
	userID := c.Query("user_id")
	if userID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "缺少 user_id"})
		return
	}

	sig := c.Query("sig")
	if !h.verifySig(userID, sig) {
		c.JSON(http.StatusForbidden, gin.H{"error": "签名无效"})
		return
	}

	// 把 sig 一并嵌入 callback URL，让 iOS 系统回调时原样带上
	// redirect 用于支持不同场景（self-sign vs purchase）跳回各自的落地页
	callbackURL := h.BaseURL + "/api/udid/callback?user_id=" + userID
	if sig != "" {
		callbackURL += "&sig=" + sig
	}
	if r := sanitizeRedirect(c.Query("redirect")); r != "" {
		callbackURL += "&redirect=" + url.QueryEscape(r)
	}
	payloadUUID := uuid.New().String()

	config, err := udid.GenerateMobileConfig(callbackURL, payloadUUID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "生成配置文件失败"})
		return
	}

	c.Header("Content-Type", "application/x-apple-aspen-config")
	c.Header("Content-Disposition", "attachment; filename=\"udid.mobileconfig\"")
	c.Data(http.StatusOK, "application/x-apple-aspen-config", config)
}

// UDIDCallback 接收 iOS 系统回传的 UDID 数据
// POST /api/udid/callback?user_id=xxx&sig=xxx
func (h *UDIDHandler) UDIDCallback(c *gin.Context) {
	userIDStr := c.Query("user_id")
	sig := c.Query("sig")

	// 签名校验：登录用户的绑定必须来自服务端发出的 config
	if !h.verifySig(userIDStr, sig) {
		log.Printf("UDID 回调: 签名无效 user_id=%s", userIDStr)
		c.Status(http.StatusForbidden)
		return
	}

	body, err := io.ReadAll(c.Request.Body)
	if err != nil {
		log.Printf("读取 UDID 回调 body 失败: %v", err)
		c.Status(http.StatusInternalServerError)
		return
	}

	// 解析设备信息
	deviceInfo := parseUDIDFromBody(body)
	if deviceInfo == nil {
		log.Printf("解析 UDID 失败, body 长度: %d", len(body))
		c.Status(http.StatusBadRequest)
		return
	}

	log.Printf("收到 UDID: user_id=%s, udid=%s, product=%s, version=%s",
		userIDStr, deviceInfo.UDID, deviceInfo.Product, deviceInfo.Version)

	// 保存到数据库（user_id=0 时暂存到 pending_devices，登录后自动迁移）
	if h.DeviceRepo != nil && userIDStr != "" {
		device := &model.Device{
			UDID:       deviceInfo.UDID,
			Model:      deviceInfo.Product,
			IOSVersion: deviceInfo.Version,
		}
		if userIDStr == "0" {
			// 匿名暂存到 pending_devices 表
			if err := h.DeviceRepo.SaveAnonymous(device); err != nil {
				log.Printf("保存匿名设备失败: %v", err)
			} else {
				log.Printf("匿名设备已暂存: udid=%s", deviceInfo.UDID)
			}
		} else {
			userID, _ := strconv.ParseInt(userIDStr, 10, 64)
			device.UserID = userID
			if err := h.DeviceRepo.Save(device); err != nil {
				log.Printf("保存设备失败: %v", err)
			} else {
				log.Printf("设备已保存: user_id=%d, udid=%s", userID, deviceInfo.UDID)
			}
		}
	}

	// 回调跳转：优先用 config 时指定的 redirect，否则回购买页
	redirectBase := sanitizeRedirect(c.Query("redirect"))
	if redirectBase == "" {
		redirectBase = "https://susuq.top/purchase/?udid_ok=1"
	}

	// 匿名场景（user_id=0）没有保存设备归属，UDID 只能通过 URL 回传给前端
	finalURL := redirectBase
	if userIDStr == "0" && deviceInfo.UDID != "" {
		sep := "?"
		if strings.Contains(finalURL, "?") {
			sep = "&"
		}
		finalURL = finalURL + sep + "udid=" + url.QueryEscape(deviceInfo.UDID)
	}
	c.Redirect(http.StatusMovedPermanently, finalURL)
}

// DeviceInfo 设备信息
type DeviceInfo struct {
	UDID    string
	IMEI    string
	ICCID   string
	Version string
	Product string
	Serial  string
}

// CheckUDID 检查用户是否已有 UDID 记录
// GET /api/udid/check?user_id=xxx&sig=xxx
// 登录用户查自己的 UDID 必须带 sig；user_id=0 匿名查询 pending_devices 表
func (h *UDIDHandler) CheckUDID(c *gin.Context) {
	userIDStr := c.Query("user_id")
	if userIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "缺少 user_id"})
		return
	}

	// 匿名查询：查 pending_devices 表
	if userIDStr == "0" {
		if h.DeviceRepo == nil {
			c.JSON(http.StatusOK, gin.H{"success": true, "data": gin.H{"found": false}})
			return
		}
		pending, err := h.DeviceRepo.FindPending()
		if err != nil || pending == nil {
			c.JSON(http.StatusOK, gin.H{"success": true, "data": gin.H{"found": false}})
			return
		}
		c.JSON(http.StatusOK, gin.H{
			"success": true,
			"data": gin.H{
				"found": true,
				"udid":  pending.UDID,
			},
		})
		return
	}

	// 登录用户查询：必须带 sig
	sig := c.Query("sig")
	if !h.verifySig(userIDStr, sig) {
		c.JSON(http.StatusForbidden, gin.H{"success": false, "error": "签名无效"})
		return
	}

	userID, err := strconv.ParseInt(userIDStr, 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "user_id 格式错误"})
		return
	}

	if h.DeviceRepo == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "数据库不可用"})
		return
	}

	devices, err := h.DeviceRepo.FindByUserID(userID)
	if err != nil {
		log.Printf("查询用户设备失败: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "查询失败"})
		return
	}

	if len(devices) > 0 {
		c.JSON(http.StatusOK, gin.H{
			"success": true,
			"data": gin.H{
				"found": true,
				"udid":  devices[0].UDID,
			},
		})
	} else {
		c.JSON(http.StatusOK, gin.H{
			"success": true,
			"data": gin.H{
				"found": false,
			},
		})
	}
}

// parseUDIDFromBody 从 iOS 回调的签名 plist 中提取设备信息
func parseUDIDFromBody(body []byte) *DeviceInfo {
	info := &DeviceInfo{}
	info.UDID = extractPlistValueBytes(body, "UDID")
	info.Product = extractPlistValueBytes(body, "PRODUCT")
	info.Version = extractPlistValueBytes(body, "VERSION")
	info.Serial = extractPlistValueBytes(body, "SERIAL")
	info.IMEI = extractPlistValueBytes(body, "IMEI")

	if info.UDID == "" {
		return nil
	}
	return info
}

// extractPlistValueBytes 从二进制数据中的 plist XML 提取指定 key 的值
func extractPlistValueBytes(content []byte, key string) string {
	keyTag := []byte("<key>" + key + "</key>")
	idx := bytes.Index(content, keyTag)
	if idx < 0 {
		return ""
	}

	rest := content[idx+len(keyTag):]
	startTag := []byte("<string>")
	endTag := []byte("</string>")

	startIdx := bytes.Index(rest, startTag)
	if startIdx < 0 {
		return ""
	}
	rest = rest[startIdx+len(startTag):]

	endIdx := bytes.Index(rest, endTag)
	if endIdx < 0 {
		return ""
	}

	return string(rest[:endIdx])
}
