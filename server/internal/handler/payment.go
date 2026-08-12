package handler

import (
	"fmt"
	"log"
	"math"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/haifeng/jisign-server/internal/payment"
	"github.com/haifeng/jisign-server/internal/repository"
	"github.com/haifeng/jisign-server/internal/service"
)

// PaymentHandler 支付处理
type PaymentHandler struct {
	Alipay           *payment.AlipayClient
	OrderRepo        *repository.OrderRepo
	CertService      *service.CertService
	ExpectedAppID    string // 支付宝应用 ID，用于校验回调身份
	ExpectedSellerID string // 商户 PID（seller_id / pid），用于校验回调身份
}

// CreatePaymentRequest 创建支付请求
type CreatePaymentRequest struct {
	OrderNo     string `json:"order_no" binding:"required"`
	PaymentType string `json:"payment_type"` // 可选：auto / wap / page（空则自动检测）
}

// CreatePayment 创建支付宝支付
// POST /api/pay/alipay/create
func (h *PaymentHandler) CreatePayment(c *gin.Context) {
	if h.Alipay == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"success": false, "error": "支付功能暂未开启"})
		return
	}

	var req CreatePaymentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "参数错误"})
		return
	}

	userID := c.GetInt64("user_id")

	// 查询订单
	order, err := h.OrderRepo.FindByOrderNo(req.OrderNo)
	if err != nil || order == nil {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "订单不存在"})
		return
	}

	// 验证订单归属
	if order.UserID != userID {
		c.JSON(http.StatusForbidden, gin.H{"success": false, "error": "无权操作此订单"})
		return
	}

	// 验证订单状态
	if order.PaymentStatus != "pending" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "订单状态不正确"})
		return
	}

	// 自动检测支付方式：客户端指定 > User-Agent 检测
	paymentType := req.PaymentType
	if paymentType == "" || paymentType == "auto" {
		paymentType = detectPaymentType(c.GetHeader("User-Agent"))
	}

	var payURL string

	switch paymentType {
	case "wap":
		// 手机网站支付
		payURL, err = h.Alipay.CreateWapPayment(
			order.OrderNo,
			order.Amount,
			"速签 - 个人开发者证书",
		)
	default:
		// 电脑网站支付（默认）
		payURL, err = h.Alipay.CreatePagePayment(
			order.OrderNo,
			order.Amount,
			"速签 - 个人开发者证书",
		)
	}

	if err != nil {
		log.Printf("创建支付失败: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "创建支付失败"})
		return
	}

	log.Printf("创建支付: orderNo=%s, type=%s, amount=%.2f", order.OrderNo, paymentType, order.Amount)

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data": gin.H{
			"payment_url":  payURL,
			"order_no":     order.OrderNo,
			"amount":       order.Amount,
			"payment_type": paymentType,
		},
	})
}

// AlipayNotify 支付宝异步通知回调
// POST /api/pay/alipay/notify
func (h *PaymentHandler) AlipayNotify(c *gin.Context) {
	if h.Alipay == nil {
		c.String(http.StatusOK, "fail")
		return
	}

	// 解析表单数据
	if err := c.Request.ParseForm(); err != nil {
		log.Printf("解析支付宝通知表单失败: %v", err)
		c.String(http.StatusOK, "fail")
		return
	}

	// 验证签名
	notification, err := h.Alipay.VerifyNotify(c.Request.PostForm)
	if err != nil {
		log.Printf("支付宝回调验签失败: %v", err)
		c.String(http.StatusOK, "fail")
		return
	}

	// 校验商户身份（防止只要通过了支付宝签名就能伪造本项目订单）
	if h.ExpectedAppID != "" && notification.AppId != h.ExpectedAppID {
		log.Printf("支付宝回调: app_id 不匹配, 期望=%s 实际=%s", h.ExpectedAppID, notification.AppId)
		c.String(http.StatusOK, "fail")
		return
	}
	if h.ExpectedSellerID != "" && notification.SellerId != h.ExpectedSellerID {
		log.Printf("支付宝回调: seller_id 不匹配, 期望=%s 实际=%s", h.ExpectedSellerID, notification.SellerId)
		c.String(http.StatusOK, "fail")
		return
	}

	orderNo := notification.OutTradeNo
	tradeStatus := string(notification.TradeStatus)

	log.Printf("支付宝回调: orderNo=%s, status=%s, amount=%s",
		orderNo, tradeStatus, notification.TotalAmount)

	// 查询订单
	order, err := h.OrderRepo.FindByOrderNo(orderNo)
	if err != nil || order == nil {
		log.Printf("支付宝回调: 订单不存在 orderNo=%s", orderNo)
		c.String(http.StatusOK, "fail")
		return
	}

	// 幂等性检查：如果订单已支付，直接返回成功
	if order.PaymentStatus == "paid" {
		log.Printf("支付宝回调: 订单已支付，跳过 orderNo=%s", orderNo)
		c.String(http.StatusOK, "success")
		return
	}

	// 验证金额（用"分"对比，避免浮点精度问题）
	orderCents := int64(math.Round(order.Amount * 100))
	var paidAmount float64
	fmt.Sscanf(notification.TotalAmount, "%f", &paidAmount)
	paidCents := int64(math.Round(paidAmount * 100))

	if orderCents != paidCents {
		log.Printf("支付宝回调: 金额不匹配 orderNo=%s, 订单=%d分, 支付=%d分",
			orderNo, orderCents, paidCents)
		c.String(http.StatusOK, "fail")
		return
	}

	// 根据交易状态处理
	if payment.IsTradeSuccess(tradeStatus) {
		// 支付成功 → 更新订单状态
		if err := h.OrderRepo.UpdatePaymentStatus(orderNo, "paid"); err != nil {
			log.Printf("更新订单状态失败: %v", err)
			c.String(http.StatusOK, "fail")
			return
		}
		log.Printf("订单支付成功: orderNo=%s, amount=%.2f", orderNo, order.Amount)

		// 异步触发证书生成（订单里已包含 UDID，不依赖客户端）
		// GenerateCertForOrder 内部按 orderNo 幂等，重复回调不会重复生成
		if h.CertService != nil && order.UDID != "" {
			go func(orderNo string) {
				if _, err := h.CertService.GenerateCertForOrder(orderNo); err != nil {
					log.Printf("订单 %s 自动生成证书失败: %v（用户可在 App 端重试）", orderNo, err)
				}
			}(orderNo)
		}

		c.String(http.StatusOK, "success")
	} else if tradeStatus == "TRADE_CLOSED" {
		// 交易关闭 — 写库失败需要返回 fail 让支付宝重试
		if err := h.OrderRepo.UpdatePaymentStatus(orderNo, "closed"); err != nil {
			log.Printf("更新 TRADE_CLOSED 状态失败: orderNo=%s, err=%v", orderNo, err)
			c.String(http.StatusOK, "fail")
			return
		}
		c.String(http.StatusOK, "success")
	} else if tradeStatus == "WAIT_BUYER_PAY" {
		// 等待付款，中间状态
		c.String(http.StatusOK, "success")
	} else {
		log.Printf("支付宝回调: 未知状态 status=%s, orderNo=%s", tradeStatus, orderNo)
		c.String(http.StatusOK, "fail")
	}
}

// AlipayReturn 支付宝同步回调（用户支付后跳转）
// GET /api/pay/alipay/return
func (h *PaymentHandler) AlipayReturn(c *gin.Context) {
	orderNo := c.Query("out_trade_no")
	// 跳回购买页面，带上订单号让前端自动检测支付结果
	c.Redirect(http.StatusFound, "https://susuq.top/purchase/?paid="+orderNo)
}

// detectPaymentType 根据 User-Agent 自动检测支付方式
// 移动端 → wap（手机网站支付），PC端 → page（电脑网站支付）
func detectPaymentType(ua string) string {
	ua = strings.ToLower(ua)
	mobileKeywords := []string{
		"android", "iphone", "ipad", "ipod",
		"micromessenger", "alipay", "weibo",
		"ucbrowser", "mqq", "mobile",
	}
	for _, kw := range mobileKeywords {
		if strings.Contains(ua, kw) {
			return "wap"
		}
	}
	return "page"
}
