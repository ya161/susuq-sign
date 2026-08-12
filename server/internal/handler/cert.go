package handler

import (
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/haifeng/jisign-server/internal/model"
	"github.com/haifeng/jisign-server/internal/neicexia"
	"github.com/haifeng/jisign-server/internal/repository"
	"github.com/haifeng/jisign-server/internal/service"
)

// CertHandler 证书管理处理
type CertHandler struct {
	CertService    *service.CertService
	CertRepo       *repository.CertRepo
	Neicexia       *neicexia.Client
	InstallHandler *InstallHandler // 用于证书生成后预签名 IPA
}

// PurchaseRequest 购买证书请求
type PurchaseRequest struct {
	UDID          string `json:"udid" binding:"required"`
	ProductType   string `json:"product_type" binding:"required"`   // personal_cert / enterprise_cert
	PaymentMethod string `json:"payment_method" binding:"required"` // wechat / alipay
}

// Price 获取产品价格（公开接口，供 Web/iOS 展示）
// GET /api/cert/price?product_type=personal_cert
func (h *CertHandler) Price(c *gin.Context) {
	productType := c.DefaultQuery("product_type", "personal_cert")
	amount, ok := service.GetPrice(productType)
	if !ok {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "不支持的产品类型"})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data": gin.H{
			"product_type": productType,
			"amount":       amount,
			"currency":     "CNY",
		},
	})
}

// Purchase 购买证书（创建订单）
// POST /api/cert/purchase
func (h *CertHandler) Purchase(c *gin.Context) {
	var req PurchaseRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "参数错误: " + err.Error()})
		return
	}

	userID := c.GetInt64("user_id")

	result, err := h.CertService.CreateOrder(userID, req.ProductType, req.PaymentMethod, req.UDID)
	if err != nil {
		log.Printf("创建订单失败: %v", err)
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data": gin.H{
			"order_no":     result.OrderNo,
			"amount":       result.Amount,
			"product_type": req.ProductType,
		},
	})
}

// GenerateCertRequest 生成证书请求
type GenerateCertRequest struct {
	OrderNo string `json:"order_no" binding:"required"`
	UDID    string `json:"udid" binding:"required"`
}

// GenerateCert 支付成功后生成证书
// POST /api/cert/generate
func (h *CertHandler) GenerateCert(c *gin.Context) {
	var req GenerateCertRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "参数错误"})
		return
	}

	userID := c.GetInt64("user_id")

	result, err := h.CertService.GenerateCert(userID, req.OrderNo, req.UDID)
	if err != nil {
		log.Printf("生成证书失败: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": err.Error()})
		return
	}

	// 异步预签名 IPA，这样用户点安装时无需等待
	if h.InstallHandler != nil && result.UDIDBatchNo != "" {
		go h.InstallHandler.PreSignIPA(result.UDIDBatchNo)
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    result,
	})
}

// List 获取用户的证书列表
// GET /api/cert/list
func (h *CertHandler) List(c *gin.Context) {
	userID := c.GetInt64("user_id")

	certs, err := h.CertRepo.FindByUserID(userID)
	if err != nil {
		log.Printf("查询证书列表失败: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "查询证书列表失败"})
		return
	}

	// 确保返回空数组而非 null
	if certs == nil {
		certs = []model.Certificate{}
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    certs,
	})
}

// CheckValid 检查证书有效性
// POST /api/cert/check/:id
func (h *CertHandler) CheckValid(c *gin.Context) {
	batchNo := c.Query("batch_no")
	if batchNo == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "缺少批次号"})
		return
	}

	valid, err := h.Neicexia.CheckCertValid(batchNo)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    gin.H{"valid": valid},
	})
}

// DownloadCertRequest 下载证书请求
type DownloadCertRequest struct {
	BatchNo string `json:"batch_no" binding:"required"`
}

// DownloadCert 下载证书文件（P12 + mobileprovision）
// POST /api/cert/download
func (h *CertHandler) DownloadCert(c *gin.Context) {
	var req DownloadCertRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "参数错误"})
		return
	}

	userID := c.GetInt64("user_id")

	// 查找证书记录
	cert, err := h.CertRepo.FindByBatchNo(req.BatchNo)
	if err != nil || cert == nil {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "证书不存在"})
		return
	}

	// 验证归属
	if cert.UserID != userID {
		c.JSON(http.StatusForbidden, gin.H{"success": false, "error": "无权操作此证书"})
		return
	}

	// 获取设备 UDID
	var udid string
	if cert.DeviceID > 0 && h.CertService.DeviceRepo != nil {
		devices, _ := h.CertService.DeviceRepo.FindByUserID(userID)
		if len(devices) > 0 {
			udid = devices[0].UDID
		}
	}
	if udid == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "找不到设备 UDID"})
		return
	}

	// 从内测侠获取证书文件
	result, err := h.Neicexia.QueryCert(udid)
	if err != nil {
		log.Printf("查询证书文件失败: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "获取证书文件失败"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data": gin.H{
			"p12_data":              result.P12FileData,
			"mobileprovision_data":  result.MobileProvisionFileData,
			"udid_batch_no":         req.BatchNo,
		},
	})
}
