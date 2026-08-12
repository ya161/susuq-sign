package service

import (
	"fmt"
	"log"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/haifeng/jisign-server/internal/model"
	"github.com/haifeng/jisign-server/internal/neicexia"
	"github.com/haifeng/jisign-server/internal/repository"
)

// CertService 证书业务逻辑
type CertService struct {
	CertRepo   *repository.CertRepo
	OrderRepo  *repository.OrderRepo
	DeviceRepo *repository.DeviceRepo
	Neicexia   *neicexia.Client
}

// NewCertService 创建证书服务
func NewCertService(certRepo *repository.CertRepo, orderRepo *repository.OrderRepo,
	deviceRepo *repository.DeviceRepo, nxClient *neicexia.Client) *CertService {
	return &CertService{
		CertRepo:   certRepo,
		OrderRepo:  orderRepo,
		DeviceRepo: deviceRepo,
		Neicexia:   nxClient,
	}
}

// PurchaseResult 购买结果
type PurchaseResult struct {
	OrderNo string  `json:"order_no"`
	Amount  float64 `json:"amount"`
}

// GenerateCertResult 证书生成结果
type GenerateCertResult struct {
	P12Data             string `json:"p12_data"`
	MobileProvisionData string `json:"mobileprovision_data"`
	UDIDBatchNo         string `json:"udid_batch_no"`
}

// 产品价格表
var productPrices = map[string]float64{
	"personal_cert":   69.00, // 正式价格；测试时改为 0.01
	"enterprise_cert": 299.00,
}

// GetPrice 获取产品价格
func GetPrice(productType string) (float64, bool) {
	p, ok := productPrices[productType]
	return p, ok
}

// AllPrices 返回所有产品价格（给前端展示用）
func AllPrices() map[string]float64 {
	out := make(map[string]float64, len(productPrices))
	for k, v := range productPrices {
		out[k] = v
	}
	return out
}

// CreateOrder 创建购买订单
func (s *CertService) CreateOrder(userID int64, productType string, paymentMethod string, udid string) (*PurchaseResult, error) {
	// 校验产品类型
	amount, ok := productPrices[productType]
	if !ok {
		return nil, fmt.Errorf("不支持的产品类型: %s", productType)
	}

	// 生成订单号
	orderNo := generateOrderNo()

	order := &model.Order{
		UserID:        userID,
		OrderNo:       orderNo,
		ProductType:   productType,
		Amount:        amount,
		UDID:          udid,
		PaymentMethod: paymentMethod,
		PaymentStatus: "pending",
	}

	if err := s.OrderRepo.Create(order); err != nil {
		return nil, fmt.Errorf("创建订单失败: %w", err)
	}

	return &PurchaseResult{
		OrderNo: orderNo,
		Amount:  amount,
	}, nil
}

// GenerateCert 支付成功后生成证书（API 入口，校验用户身份）
// udidParam 参数仅做向后兼容，实际使用 order.UDID（防止客户端伪造 UDID 签证书）
func (s *CertService) GenerateCert(userID int64, orderNo string, udidParam string) (*GenerateCertResult, error) {
	// 验证订单
	order, err := s.OrderRepo.FindByOrderNo(orderNo)
	if err != nil {
		return nil, fmt.Errorf("查询订单失败: %w", err)
	}
	if order == nil {
		return nil, fmt.Errorf("订单不存在: %s", orderNo)
	}
	if order.UserID != userID {
		return nil, fmt.Errorf("无权操作此订单")
	}
	if order.PaymentStatus != "paid" {
		return nil, fmt.Errorf("订单未支付")
	}

	return s.generateCertLocked(order)
}

// GenerateCertForOrder 内部入口（支付回调异步调用），不做用户身份校验
// 订单已由支付回调验证过归属
func (s *CertService) GenerateCertForOrder(orderNo string) (*GenerateCertResult, error) {
	order, err := s.OrderRepo.FindByOrderNo(orderNo)
	if err != nil {
		return nil, fmt.Errorf("查询订单失败: %w", err)
	}
	if order == nil {
		return nil, fmt.Errorf("订单不存在: %s", orderNo)
	}
	if order.PaymentStatus != "paid" {
		return nil, fmt.Errorf("订单未支付")
	}
	return s.generateCertLocked(order)
}

// generateCertLocked 核心生成逻辑，按 order.UDID 幂等
// 已有证书记录 → 复用内测侠 QueryCert 拉取同一套文件返回
// 没有 → 新建
func (s *CertService) generateCertLocked(order *model.Order) (*GenerateCertResult, error) {
	if order.UDID == "" {
		return nil, fmt.Errorf("订单缺少 UDID，无法生成证书")
	}
	udid := order.UDID
	userID := order.UserID

	// 幂等：查用户名下是否已有 UDID 的证书
	// 通过 DeviceRepo.FindByUDID 找到设备后查 certificates
	device, err := s.DeviceRepo.FindByUDID(udid)
	if err != nil {
		return nil, fmt.Errorf("查询设备失败: %w", err)
	}

	var deviceID int64
	if device != nil {
		deviceID = device.ID
		// 检查该用户该设备是否已有 active 证书
		existingCerts, err := s.CertRepo.FindByUserID(userID)
		if err == nil {
			for _, cert := range existingCerts {
				if cert.DeviceID == deviceID && cert.Status == "active" {
					// 已有证书 → 直接 QueryCert 拉取文件返回，不重复 CreateUDIDCert
					qr, err := s.Neicexia.QueryCert(udid)
					if err == nil && qr.P12FileData != "" {
						log.Printf("幂等命中: orderNo=%s, batchNo=%s", order.OrderNo, cert.UDIDBatchNo)
						return &GenerateCertResult{
							P12Data:             qr.P12FileData,
							MobileProvisionData: qr.MobileProvisionFileData,
							UDIDBatchNo:         cert.UDIDBatchNo,
						}, nil
					}
					// QueryCert 失败（如内测侠侧证书已失效），继续走下面的 CreateUDIDCert
					log.Printf("幂等查询失败，重新生成: orderNo=%s, err=%v", order.OrderNo, err)
					break
				}
			}
		}
	}

	// 调用内测侠 API 生成证书
	result, err := s.Neicexia.CreateUDIDCert(udid, "public")
	if err != nil {
		return nil, fmt.Errorf("调用内测侠生成证书失败: %w", err)
	}

	// 保存证书记录
	cert := &model.Certificate{
		UserID:      userID,
		DeviceID:    deviceID,
		UDIDBatchNo: result.UDIDBatchNo,
		CerAppleID:  result.CerAppleID,
		PoolType:    "public",
		Status:      "active",
	}

	if err := s.CertRepo.Save(cert); err != nil {
		return nil, fmt.Errorf("保存证书记录失败: %w", err)
	}

	return &GenerateCertResult{
		P12Data:             result.P12FileData,
		MobileProvisionData: result.MobileProvisionFileData,
		UDIDBatchNo:         result.UDIDBatchNo,
	}, nil
}

// CheckAllCerts 定时检查所有活跃证书的有效性
func (s *CertService) CheckAllCerts() {
	certs, err := s.CertRepo.FindActiveCerts()
	if err != nil {
		log.Printf("获取活跃证书列表失败: %v", err)
		return
	}

	log.Printf("开始检查 %d 个活跃证书", len(certs))

	for _, cert := range certs {
		valid, err := s.Neicexia.CheckCertValid(cert.UDIDBatchNo)
		if err != nil {
			log.Printf("检查证书 %d (batch=%s) 失败: %v", cert.ID, cert.UDIDBatchNo, err)
			continue
		}

		if !valid {
			log.Printf("证书 %d (batch=%s) 已失效，更新状态为 revoked", cert.ID, cert.UDIDBatchNo)
			if err := s.CertRepo.UpdateStatus(cert.ID, "revoked"); err != nil {
				log.Printf("更新证书状态失败: %v", err)
			}
		}
	}

	log.Printf("证书检查完成")
}

// StartCertChecker 启动证书有效性定时检查（每 6 小时检查一次）
func (s *CertService) StartCertChecker() {
	ticker := time.NewTicker(6 * time.Hour)
	go func() {
		for range ticker.C {
			s.CheckAllCerts()
		}
	}()
	log.Println("证书有效性定时检查已启动（每 6 小时）")
}

// generateOrderNo 生成订单号：JS + UUID 前16位（去除连字符）
func generateOrderNo() string {
	return "JS" + strings.ReplaceAll(uuid.New().String(), "-", "")[:16]
}
