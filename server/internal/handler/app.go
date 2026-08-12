package handler

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/haifeng/jisign-server/internal/repository"
)

// AppHandler App 版本管理
type AppHandler struct {
	CertRepo   *repository.CertRepo
	DeviceRepo *repository.DeviceRepo
	BaseURL    string
}

// 当前最新版本信息（后续可改为数据库管理）
const (
	latestVersion = "1.0.51"
	latestBuild   = "48"
	updateNote    = "证书价格调整为 ¥69/年"
)

// VersionInfo 版本检查
// GET /api/app/version
func (h *AppHandler) VersionInfo(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data": gin.H{
			"version":     latestVersion,
			"build":       latestBuild,
			"update_note": updateNote,
			"force":       false,
		},
	})
}

// UpdateApp 获取更新安装链接（需要登录）
// POST /api/app/update
func (h *AppHandler) UpdateApp(c *gin.Context) {
	userID := c.GetInt64("user_id")
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "请先登录"})
		return
	}

	// 查找用户的有效证书
	certs, err := h.CertRepo.FindByUserID(userID)
	if err != nil || len(certs) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "未找到有效证书，请先购买证书"})
		return
	}

	// 使用最新的证书
	cert := certs[0]
	if cert.Status != "active" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "证书已过期，请重新购买"})
		return
	}

	// 返回安装链接（使用已有的 install manifest 接口）
	batchNo := cert.UDIDBatchNo
	installURL := "itms-services://?action=download-manifest&url=" + h.BaseURL + "/api/install/manifest/" + batchNo

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data": gin.H{
			"install_url": installURL,
			"batch_no":    batchNo,
			"version":     latestVersion,
		},
	})
}
