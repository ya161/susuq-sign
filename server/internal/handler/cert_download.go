package handler

import (
	"encoding/base64"
	"fmt"
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/haifeng/jisign-server/internal/yiqian"
)

// CertDownloadHandler 证书下载处理
type CertDownloadHandler struct {
	YiqianClient *yiqian.Client
}

// DownloadCertByUDIDRequest 通过UDID下载证书请求
type DownloadCertByUDIDRequest struct {
	UDID    string `json:"udid" binding:"required"`
	CertType int   `json:"cert_type"` // 0躺平版 1标准版 2加强版 3稳定版，默认1
}

// DownloadCertResponse 下载证书响应
type DownloadCertResponse struct {
	CertID             string `json:"cert_id"`               // 证书ID
	P12Data            []byte `json:"-"`                     // P12 二进制数据
	MobileProvisionData []byte `json:"-"`                    // 描述文件二进制数据
	P12Base64          string `json:"p12_base64"`            // base64 P12（供前端使用）
	MobileProvisionBase64 string `json:"mobileprovision_base64"` // base64 描述文件（供前端使用）
	State              bool   `json:"state"`                 // 证书状态
}

// DownloadCert 下载证书文件（P12 + mobileprovision）
// POST /api/cert/download-yiqian
func (h *CertDownloadHandler) DownloadCert(c *gin.Context) {
	var req DownloadCertByUDIDRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "参数错误: " + err.Error()})
		return
	}

	// 默认使用标准版证书
	if req.CertType == 0 {
		req.CertType = 1
	}

	// 调用易签 API 添加设备
	result, err := h.YiqianClient.AddDevice(
		req.UDID,
		yiqian.CertificateType(req.CertType),
		yiqian.DevicePoolPublic, // 使用公共池
	)
	if err != nil {
		log.Printf("调用易签API失败: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "证书生成失败: " + err.Error(),
		})
		return
	}

	// 解码 base64 数据
	p12Data, err := base64.StdEncoding.DecodeString(result.P12)
	if err != nil {
		log.Printf("解码P12数据失败: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "证书数据解码失败",
		})
		return
	}

	mpData, err := base64.StdEncoding.DecodeString(result.MobileProvision)
	if err != nil {
		log.Printf("解码描述文件数据失败: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "描述文件数据解码失败",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data": gin.H{
			"cert_id":               result.ID,
			"p12_base64":            result.P12,
			"mobileprovision_base64": result.MobileProvision,
			"p12_size":              len(p12Data),
			"mobileprovision_size":  len(mpData),
			"state":                 result.State,
		},
	})
}

// DownloadCertFile 下载证书文件（二进制格式）
// GET /api/cert/download-file?type=p12&udid=xxx
func (h *CertDownloadHandler) DownloadCertFile(c *gin.Context) {
	fileType := c.Query("type") // p12 或 mobileprovision
	udid := c.Query("udid")

	if udid == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "缺少 UDID 参数"})
		return
	}

	if fileType != "p12" && fileType != "mobileprovision" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "无效的文件类型，支持: p12, mobileprovision"})
		return
	}

	// 调用易签 API
	result, err := h.YiqianClient.AddDevice(
		udid,
		yiqian.CertTypeStandard,
		yiqian.DevicePoolPublic,
	)
	if err != nil {
		log.Printf("调用易签API失败: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "证书生成失败",
		})
		return
	}

	// 解码并返回文件
	var fileData []byte
	var fileName string

	if fileType == "p12" {
		fileData, err = base64.StdEncoding.DecodeString(result.P12)
		fileName = fmt.Sprintf("certificate_%s.p12", result.ID)
	} else {
		fileData, err = base64.StdEncoding.DecodeString(result.MobileProvision)
		fileName = fmt.Sprintf("certificate_%s.mobileprovision", result.ID)
	}

	if err != nil {
		log.Printf("解码文件数据失败: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "文件数据解码失败",
		})
		return
	}

	// 设置响应头，返回文件下载
	c.Header("Content-Disposition", fmt.Sprintf("attachment; filename=%s", fileName))
	c.Header("Content-Type", "application/octet-stream")
	c.Data(http.StatusOK, "application/octet-stream", fileData)
}

// GetBalance 获取易签账号余额
// GET /api/cert/yiqian-balance
func (h *CertDownloadHandler) GetBalance(c *gin.Context) {
	result, err := h.YiqianClient.GetBalance()
	if err != nil {
		log.Printf("查询易签余额失败: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "查询余额失败: " + err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data": gin.H{
			"score":   result.Score,
			"balance": result.Balance,
		},
	})
}
