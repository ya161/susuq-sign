package sms

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"crypto/hmac"
	"crypto/sha1"
	"encoding/base64"
	"math/rand"
	"sort"
	"strings"
	"time"
)

// AliyunSMSClient 阿里云短信客户端
type AliyunSMSClient struct {
	AccessKeyID     string
	AccessKeySecret string
	SignName        string // 短信签名，如"速签"
	TemplateCode    string // 短信模板 ID，如 SMS_498310069
}

// NewAliyunSMSClient 创建阿里云短信客户端
func NewAliyunSMSClient(keyID, keySecret, signName, templateCode string) *AliyunSMSClient {
	return &AliyunSMSClient{
		AccessKeyID:     keyID,
		AccessKeySecret: keySecret,
		SignName:        signName,
		TemplateCode:    templateCode,
	}
}

// AliyunSMSResponse 阿里云 SMS API 响应
type AliyunSMSResponse struct {
	Code      string `json:"Code"`
	Message   string `json:"Message"`
	RequestID string `json:"RequestId"`
	BizID     string `json:"BizId"`
}

// SendCode 发送验证码短信
// phone: 手机号（如 13800138000）
// code: 验证码（如 123456）
func (c *AliyunSMSClient) SendCode(phone, code string) error {
	// 模板参数
	templateParam, _ := json.Marshal(map[string]string{
		"code": code,
	})

	// 构建请求参数
	params := map[string]string{
		"Action":           "SendSms",
		"Version":          "2017-05-25",
		"RegionId":         "cn-hangzhou",
		"PhoneNumbers":     phone,
		"SignName":         c.SignName,
		"TemplateCode":     c.TemplateCode,
		"TemplateParam":    string(templateParam),
		"Format":           "JSON",
		"SignatureMethod":  "HMAC-SHA1",
		"SignatureVersion": "1.0",
		"SignatureNonce":   fmt.Sprintf("%d%d", time.Now().UnixNano(), rand.Intn(10000)),
		"Timestamp":        time.Now().UTC().Format("2006-01-02T15:04:05Z"),
		"AccessKeyId":      c.AccessKeyID,
	}

	// 生成签名
	signature := c.sign(params)
	params["Signature"] = signature

	// 构建请求 URL
	values := url.Values{}
	for k, v := range params {
		values.Set(k, v)
	}

	reqURL := "https://dysmsapi.aliyuncs.com/?" + values.Encode()

	// 发送请求
	resp, err := http.Get(reqURL)
	if err != nil {
		return fmt.Errorf("发送短信请求失败: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("读取短信响应失败: %w", err)
	}

	var smsResp AliyunSMSResponse
	if err := json.Unmarshal(body, &smsResp); err != nil {
		return fmt.Errorf("解析短信响应失败: %w", err)
	}

	if smsResp.Code != "OK" {
		return fmt.Errorf("短信发送失败: %s (%s)", smsResp.Message, smsResp.Code)
	}

	return nil
}

// sign 生成阿里云 API 签名
func (c *AliyunSMSClient) sign(params map[string]string) string {
	// 1. 将参数按 key 排序
	keys := make([]string, 0, len(params))
	for k := range params {
		keys = append(keys, k)
	}
	sort.Strings(keys)

	// 2. 构建规范化请求字符串
	var pairs []string
	for _, k := range keys {
		pairs = append(pairs, specialURLEncode(k)+"="+specialURLEncode(params[k]))
	}
	canonicalizedQuery := strings.Join(pairs, "&")

	// 3. 构建待签名字符串
	stringToSign := "GET&" + specialURLEncode("/") + "&" + specialURLEncode(canonicalizedQuery)

	// 4. HMAC-SHA1 签名
	mac := hmac.New(sha1.New, []byte(c.AccessKeySecret+"&"))
	mac.Write([]byte(stringToSign))
	signature := base64.StdEncoding.EncodeToString(mac.Sum(nil))

	return signature
}

// specialURLEncode 阿里云要求的特殊 URL 编码
func specialURLEncode(s string) string {
	encoded := url.QueryEscape(s)
	encoded = strings.ReplaceAll(encoded, "+", "%20")
	encoded = strings.ReplaceAll(encoded, "*", "%2A")
	encoded = strings.ReplaceAll(encoded, "%7E", "~")
	return encoded
}
