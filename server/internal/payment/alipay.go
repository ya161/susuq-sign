package payment

import (
	"context"
	"fmt"
	"log"
	"net/url"
	"os"

	"github.com/smartwalle/alipay/v3"
)

// AlipayClient 支付宝支付客户端
type AlipayClient struct {
	client    *alipay.Client
	notifyURL string // 异步通知回调地址
	returnURL string // 同步回调地址
}

// AlipayConfig 支付宝配置
type AlipayConfig struct {
	AppID              string // 支付宝应用 ID
	PrivateKeyPath     string // 应用私钥文件路径
	AppCertPath        string // 应用公钥证书路径
	AlipayPublicCertPath string // 支付宝公钥证书路径
	AlipayRootCertPath string // 支付宝根证书路径
	NotifyURL          string // 异步通知回调地址
	ReturnURL          string // 同步回调地址
	IsProduction       bool   // 是否生产环境（false = 沙箱）
}

// NewAlipayClient 创建支付宝客户端
func NewAlipayClient(cfg AlipayConfig) (*AlipayClient, error) {
	// 读取私钥
	privateKeyData, err := os.ReadFile(cfg.PrivateKeyPath)
	if err != nil {
		return nil, fmt.Errorf("读取支付宝私钥失败: %w", err)
	}

	// 创建客户端
	client, err := alipay.New(cfg.AppID, string(privateKeyData), cfg.IsProduction)
	if err != nil {
		return nil, fmt.Errorf("创建支付宝客户端失败: %w", err)
	}

	// 加载证书
	if err := client.LoadAppCertPublicKeyFromFile(cfg.AppCertPath); err != nil {
		return nil, fmt.Errorf("加载应用公钥证书失败: %w", err)
	}
	if err := client.LoadAliPayPublicCertFromFile(cfg.AlipayPublicCertPath); err != nil {
		return nil, fmt.Errorf("加载支付宝公钥证书失败: %w", err)
	}
	if err := client.LoadAliPayRootCertFromFile(cfg.AlipayRootCertPath); err != nil {
		return nil, fmt.Errorf("加载支付宝根证书失败: %w", err)
	}

	log.Printf("支付宝客户端初始化成功: AppID=%s, 环境=%s",
		cfg.AppID, map[bool]string{true: "生产", false: "沙箱"}[cfg.IsProduction])

	return &AlipayClient{
		client:    client,
		notifyURL: cfg.NotifyURL,
		returnURL: cfg.ReturnURL,
	}, nil
}

// CreateWapPayment 创建手机网站支付（WAP 支付）
// 返回支付跳转 URL
func (c *AlipayClient) CreateWapPayment(orderNo string, amount float64, subject string) (string, error) {
	trade := alipay.TradeWapPay{}
	trade.NotifyURL = c.notifyURL
	trade.ReturnURL = c.returnURL
	trade.Subject = subject
	trade.OutTradeNo = orderNo
	trade.TotalAmount = fmt.Sprintf("%.2f", amount)
	trade.ProductCode = "QUICK_WAP_WAY"
	trade.QuitURL = c.returnURL

	url, err := c.client.TradeWapPay(trade)
	if err != nil {
		return "", fmt.Errorf("创建 WAP 支付失败: %w", err)
	}

	return url.String(), nil
}

// CreatePagePayment 创建电脑网站支付（PC 支付）
// 返回支付跳转 URL
func (c *AlipayClient) CreatePagePayment(orderNo string, amount float64, subject string) (string, error) {
	trade := alipay.TradePagePay{}
	trade.NotifyURL = c.notifyURL
	trade.ReturnURL = c.returnURL
	trade.Subject = subject
	trade.OutTradeNo = orderNo
	trade.TotalAmount = fmt.Sprintf("%.2f", amount)
	trade.ProductCode = "FAST_INSTANT_TRADE_PAY"

	url, err := c.client.TradePagePay(trade)
	if err != nil {
		return "", fmt.Errorf("创建 PC 支付失败: %w", err)
	}

	return url.String(), nil
}

// VerifyNotify 验证异步通知签名
// 传入 gin.Context 的 Request
func (c *AlipayClient) VerifyNotify(values url.Values) (*alipay.Notification, error) {
	ctx := context.Background()
	notification, err := c.client.DecodeNotification(ctx, values)
	if err != nil {
		return nil, fmt.Errorf("验签失败: %w", err)
	}
	return notification, nil
}

// QueryTrade 查询交易状态
func (c *AlipayClient) QueryTrade(orderNo string) (*alipay.TradeQueryRsp, error) {
	ctx := context.Background()
	req := alipay.TradeQuery{
		OutTradeNo: orderNo,
	}
	rsp, err := c.client.TradeQuery(ctx, req)
	if err != nil {
		return nil, fmt.Errorf("查询交易失败: %w", err)
	}
	return rsp, nil
}

// CloseTrade 关闭交易
func (c *AlipayClient) CloseTrade(orderNo string) error {
	ctx := context.Background()
	req := alipay.TradeClose{
		OutTradeNo: orderNo,
	}
	_, err := c.client.TradeClose(ctx, req)
	if err != nil {
		return fmt.Errorf("关闭交易失败: %w", err)
	}
	return nil
}

// Refund 退款
func (c *AlipayClient) Refund(orderNo string, amount float64, reason string) error {
	ctx := context.Background()
	req := alipay.TradeRefund{
		OutTradeNo:   orderNo,
		RefundAmount: fmt.Sprintf("%.2f", amount),
		RefundReason: reason,
	}
	_, err := c.client.TradeRefund(ctx, req)
	if err != nil {
		return fmt.Errorf("退款失败: %w", err)
	}
	return nil
}

// IsTradeSuccess 判断交易是否成功
func IsTradeSuccess(status string) bool {
	return status == "TRADE_SUCCESS" || status == "TRADE_FINISHED"
}
