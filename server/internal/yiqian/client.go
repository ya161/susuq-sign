package yiqian

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const baseURL = "https://sign.getp12.com"

// Client 易签 API 客户端
type Client struct {
	Token      string
	HTTPClient *http.Client
}

// NewClient 创建客户端
func NewClient(token string) *Client {
	return &Client{
		Token:      token,
		HTTPClient: &http.Client{Timeout: 30 * time.Second},
	}
}

// APIResponse 通用响应
type APIResponse struct {
	Code int             `json:"code"`
	Msg  string          `json:"msg"`
	Time string          `json:"time"`
	Data json.RawMessage `json:"data"`
}

// AddDeviceResult 添加设备结果
type AddDeviceResult struct {
	ID                 string `json:"id"`                   // 证书ID
	PName              string `json:"pname"`                // 证书名称
	Pool               int    `json:"pool"`                 // 池类型
	AddTime            int64  `json:"addtime"`              // 添加时间
	MobileProvision    string `json:"mobileprovision"`      // base64 描述文件
	P12                string `json:"p12"`                  // base64 P12 文件
	State              bool   `json:"state"`                // 证书状态（是否掉签）
}

// BalanceResult 余额查询结果
type BalanceResult struct {
	Score   int    `json:"score"`   // 剩余设备数
	Balance string `json:"balance"` // 余额
}

// CertificateType 证书类型
type CertificateType int

const (
	CertTypeFlat     CertificateType = 0 // 躺平版
	CertTypeStandard CertificateType = 1 // 标准版
	CertTypeEnhanced CertificateType = 2 // 加强版
	CertTypeStable   CertificateType = 3 // 稳定版
)

// DeviceType 设备池类型
type DeviceType int

const (
	DevicePoolPublic  DeviceType = 0 // 公共池
	DevicePoolPrivate DeviceType = 1 // 独立池
	DevicePoolAuto    DeviceType = 2 // 自动选择（优先独立池）
)

// AddDevice 添加设备（秒出证书）
// POST https://sign.getp12.com/api/adddevice
func (c *Client) AddDevice(udid string, certType CertificateType, deviceType DeviceType) (*AddDeviceResult, error) {
	params := url.Values{}
	params.Set("udid", udid)
	params.Set("warranty", fmt.Sprintf("%d", certType))
	params.Set("type", fmt.Sprintf("%d", deviceType))
	params.Set("token", c.Token)

	resp, err := c.post("/api/adddevice", params)
	if err != nil {
		return nil, fmt.Errorf("添加设备请求失败: %w", err)
	}

	if resp.Code != 1 {
		return nil, fmt.Errorf("添加设备失败: %s (code: %d)", resp.Msg, resp.Code)
	}

	var result AddDeviceResult
	if err := json.Unmarshal(resp.Data, &result); err != nil {
		return nil, fmt.Errorf("解析设备数据失败: %w", err)
	}

	return &result, nil
}

// GetBalance 获取账号余额设备数
// POST https://sign.getp12.com/api/getbalance
func (c *Client) GetBalance() (*BalanceResult, error) {
	params := url.Values{}
	params.Set("token", c.Token)

	resp, err := c.post("/api/getbalance", params)
	if err != nil {
		return nil, fmt.Errorf("查询余额请求失败: %w", err)
	}

	if resp.Code != 1 {
		return nil, fmt.Errorf("查询余额失败: %s (code: %d)", resp.Msg, resp.Code)
	}

	var result BalanceResult
	if err := json.Unmarshal(resp.Data, &result); err != nil {
		return nil, fmt.Errorf("解析余额数据失败: %w", err)
	}

	return &result, nil
}

// post 发送 POST 请求
func (c *Client) post(path string, params url.Values) (*APIResponse, error) {
	reqURL := baseURL + path
	req, err := http.NewRequest("POST", reqURL, strings.NewReader(params.Encode()))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	httpResp, err := c.HTTPClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer httpResp.Body.Close()

	body, err := io.ReadAll(httpResp.Body)
	if err != nil {
		return nil, err
	}

	var apiResp APIResponse
	if err := json.Unmarshal(body, &apiResp); err != nil {
		return nil, fmt.Errorf("解析响应失败: %w, body: %s", err, string(body))
	}

	return &apiResp, nil
}
