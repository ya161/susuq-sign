package neicexia

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const baseURL = "https://www.neicexia.com"

// Client 内测侠 API 客户端
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
	IsSuccess    bool            `json:"IsSuccess"`
	ErrorMessage *string         `json:"ErrorMessage"`
	ErrorCode    int             `json:"ErrorCode"`
	Data         json.RawMessage `json:"Data"`
}

// CertResult 证书生成结果
type CertResult struct {
	// 注意：json tag 为 "p12_file_date" 而非 "p12_file_data"，这是内测侠 API 文档原文的拼写，保持与上游 API 一致
	P12FileData              string `json:"p12_file_date"`                // base64 格式 P12 证书，密码为 1
	MobileProvisionFileData  string `json:"mobile_provision_file_data"`   // base64 格式描述文件
	UDIDBatchNo              string `json:"udid_batch_no"`                // UDID 批次号
	CerAppleID               string `json:"cer_appleid"`                  // 使用的 Apple ID（仅独立池）
}

// CertQueryResult 证书查询结果
type CertQueryResult struct {
	UDIDBatchNo             string `json:"udid_batch_no"`
	CreateDate              string `json:"create_date"`
	ExpireDate              string `json:"expire_date"`
	IsAppleProcessing       bool   `json:"is_apple_processing"`
	MobileProvisionFileData string `json:"mobile_provision_file_data"`
	P12FileData             string `json:"p12_file_date"`
}

// CreateUDIDCert 创建 UDID 证书（接口 7）
// 只生成证书，不创建签名任务
func (c *Client) CreateUDIDCert(udid string, pool string) (*CertResult, error) {
	params := url.Values{}
	params.Set("udid", udid)
	params.Set("udid_region_pool", pool) // public / private / auto
	params.Set("gain_cer_type", "1")     // 1=新增
	params.Set("token", c.Token)

	resp, err := c.post("/public_service/create_udid_cer", params)
	if err != nil {
		return nil, fmt.Errorf("创建证书请求失败: %w", err)
	}

	if !resp.IsSuccess {
		msg := "未知错误"
		if resp.ErrorMessage != nil {
			msg = *resp.ErrorMessage
		}
		return nil, fmt.Errorf("创建证书失败: %s (code: %d)", msg, resp.ErrorCode)
	}

	var result CertResult
	if err := json.Unmarshal(resp.Data, &result); err != nil {
		return nil, fmt.Errorf("解析证书数据失败: %w", err)
	}

	return &result, nil
}

// QueryCert 查询 UDID 对应的证书（接口 3）
func (c *Client) QueryCert(udid string) (*CertQueryResult, error) {
	params := url.Values{}
	params.Set("udid", udid)
	params.Set("skip_processing_udid", "0")
	params.Set("token", c.Token)

	resp, err := c.post("/public_service/query_cer", params)
	if err != nil {
		return nil, fmt.Errorf("查询证书请求失败: %w", err)
	}

	if !resp.IsSuccess {
		msg := "未知错误"
		if resp.ErrorMessage != nil {
			msg = *resp.ErrorMessage
		}
		return nil, fmt.Errorf("查询证书失败: %s", msg)
	}

	var result CertQueryResult
	if err := json.Unmarshal(resp.Data, &result); err != nil {
		return nil, fmt.Errorf("解析查询结果失败: %w", err)
	}

	return &result, nil
}

// CheckCertValid 检查证书是否有效（接口 6）
func (c *Client) CheckCertValid(udidBatch string) (bool, error) {
	params := url.Values{}
	params.Set("udid_batch", udidBatch)
	params.Set("token", c.Token)

	resp, err := c.post("/public_service/check_cer_validate", params)
	if err != nil {
		return false, fmt.Errorf("检查证书请求失败: %w", err)
	}

	if !resp.IsSuccess {
		return false, nil
	}

	var valid bool
	if err := json.Unmarshal(resp.Data, &valid); err != nil {
		return false, fmt.Errorf("解析检查结果失败: %w", err)
	}

	return valid, nil
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
