package handler

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/haifeng/jisign-server/internal/repository"
)

// InstallHandler App 安装处理
type InstallHandler struct {
	CertRepo       *repository.CertRepo
	DeviceRepo     *repository.DeviceRepo
	BaseURL        string // https://api.susuq.top
	IPADir         string // /opt/jisign/ipa
	UnsignedIPA    string // /opt/jisign/ipa/JiSign-unsigned.ipa
	NeicexiaToken  string
	mu             sync.Mutex
}

// Manifest 生成 manifest.plist 供 itms-services 安装
// GET /api/install/manifest/:batch_no
func (h *InstallHandler) Manifest(c *gin.Context) {
	batchNo := c.Param("batch_no")

	// 检查签名后的 IPA 是否已存在，不存在则签名
	signedDir := filepath.Join(h.IPADir, "signed")
	os.MkdirAll(signedDir, 0755)
	signedIPA := filepath.Join(signedDir, batchNo+".ipa")

	if _, err := os.Stat(signedIPA); os.IsNotExist(err) {
		if err := h.signIPA(batchNo, signedIPA); err != nil {
			log.Printf("签名失败: batch=%s, err=%v", batchNo, err)
			c.String(http.StatusInternalServerError, "签名失败: "+err.Error())
			return
		}
	}

	// 读取元数据（本地安装或上传的签名 IPA 会有 .json 文件）
	bundleIdentifier := "com.jisign.JiSign"
	appTitle := "速签"
	ipaURL := h.BaseURL + "/api/install/download/" + batchNo

	metaPath := filepath.Join(signedDir, batchNo+".json")
	if metaData, err := os.ReadFile(metaPath); err == nil {
		var meta struct {
			BundleID string `json:"bundle_id"`
			AppName  string `json:"app_name"`
			IPAURL   string `json:"ipa_url"` // 本地安装时指向 127.0.0.1
		}
		if json.Unmarshal(metaData, &meta) == nil {
			if meta.BundleID != "" {
				bundleIdentifier = meta.BundleID
			}
			if meta.AppName != "" {
				appTitle = meta.AppName
			}
			if meta.IPAURL != "" {
				ipaURL = meta.IPAURL // 使用本地 URL
			}
		}
	}
	plist := fmt.Sprintf(`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>items</key>
  <array>
    <dict>
      <key>assets</key>
      <array>
        <dict>
          <key>kind</key><string>software-package</string>
          <key>url</key><string>%s</string>
        </dict>
      </array>
      <key>metadata</key>
      <dict>
        <key>bundle-identifier</key><string>%s</string>
        <key>bundle-version</key><string>1.0.0</string>
        <key>kind</key><string>software</string>
        <key>title</key><string>%s</string>
      </dict>
    </dict>
  </array>
</dict>
</plist>`, ipaURL, bundleIdentifier, appTitle)

	c.Header("Content-Type", "text/xml; charset=utf-8")
	c.String(http.StatusOK, plist)
}

// Download 下载签名后的 IPA
// GET /api/install/download/:batch_no
func (h *InstallHandler) Download(c *gin.Context) {
	batchNo := c.Param("batch_no")
	signedIPA := filepath.Join(h.IPADir, "signed", batchNo+".ipa")

	if _, err := os.Stat(signedIPA); os.IsNotExist(err) {
		c.JSON(http.StatusNotFound, gin.H{"error": "签名文件不存在"})
		return
	}

	c.Header("Content-Type", "application/octet-stream")
	c.Header("Content-Disposition", "attachment; filename=JiSign.ipa")
	c.File(signedIPA)
}

// signIPA 用用户的证书签名速签 App
func (h *InstallHandler) signIPA(batchNo string, outputPath string) error {
	h.mu.Lock()
	defer h.mu.Unlock()

	// 再次检查（防并发）
	if _, err := os.Stat(outputPath); err == nil {
		return nil
	}

	// 从数据库获取证书记录
	cert, err := h.CertRepo.FindByBatchNo(batchNo)
	if err != nil || cert == nil {
		return fmt.Errorf("证书不存在: %s", batchNo)
	}

	// 获取设备 UDID
	var deviceUDID string
	if cert.DeviceID > 0 && h.DeviceRepo != nil {
		devices, _ := h.DeviceRepo.FindByUserID(cert.UserID)
		if len(devices) > 0 {
			deviceUDID = devices[0].UDID
		}
	}
	if deviceUDID == "" {
		return fmt.Errorf("找不到设备 UDID")
	}

	// 从内测侠获取证书文件
	p12Data, mpData, err := h.queryCertFromNeicexia(deviceUDID)
	if err != nil {
		return fmt.Errorf("获取证书文件失败: %w", err)
	}

	// 保存到临时目录
	tmpDir := filepath.Join(h.IPADir, "tmp", batchNo)
	os.MkdirAll(tmpDir, 0755)
	defer os.RemoveAll(tmpDir)

	p12Path := filepath.Join(tmpDir, "cert.p12")
	mpPath := filepath.Join(tmpDir, "cert.mobileprovision")

	if err := os.WriteFile(p12Path, p12Data, 0600); err != nil {
		return fmt.Errorf("写入 P12 失败: %w", err)
	}
	if err := os.WriteFile(mpPath, mpData, 0600); err != nil {
		return fmt.Errorf("写入 mobileprovision 失败: %w", err)
	}

	// 调用 zsign 签名
	cmd := exec.Command("zsign",
		"-k", p12Path,
		"-p", "1",
		"-m", mpPath,
		"-o", outputPath,
		h.UnsignedIPA,
	)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("zsign 失败: %w, output: %s", err, string(output))
	}

	log.Printf("IPA 签名成功: batch=%s, size=%s", batchNo, outputPath)
	return nil
}

// PreSignIPA 预签名 IPA（证书生成后异步调用，消除用户安装时的等待）
func (h *InstallHandler) PreSignIPA(batchNo string) {
	signedDir := filepath.Join(h.IPADir, "signed")
	os.MkdirAll(signedDir, 0755)
	signedIPA := filepath.Join(signedDir, batchNo+".ipa")

	if _, err := os.Stat(signedIPA); err == nil {
		log.Printf("预签名跳过: batch=%s 已存在", batchNo)
		return
	}

	log.Printf("开始预签名 IPA: batch=%s", batchNo)
	if err := h.signIPA(batchNo, signedIPA); err != nil {
		log.Printf("预签名失败: batch=%s, err=%v", batchNo, err)
	} else {
		log.Printf("预签名完成: batch=%s", batchNo)
	}
}

// LocalManifest 注册本地安装的 manifest（只接收几百字节元数据，IPA 留在用户设备）
// POST /api/install/local-manifest
func (h *InstallHandler) LocalManifest(c *gin.Context) {
	var req struct {
		BundleID  string `json:"bundle_id"`
		AppName   string `json:"app_name"`
		LocalPort int    `json:"local_port"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "参数错误"})
		return
	}

	token := "local_" + uuid.New().String()
	ipaURL := fmt.Sprintf("http://127.0.0.1:%d/signed.ipa", req.LocalPort)

	// 保存 manifest 元数据
	signedDir := filepath.Join(h.IPADir, "signed")
	os.MkdirAll(signedDir, 0755)
	metaPath := filepath.Join(signedDir, token+".json")
	metaJSON := fmt.Sprintf(`{"bundle_id":"%s","app_name":"%s","ipa_url":"%s"}`,
		req.BundleID, req.AppName, ipaURL)
	os.WriteFile(metaPath, []byte(metaJSON), 0644)

	// 创建空的占位文件（让 Manifest handler 不尝试签名）
	dummyPath := filepath.Join(signedDir, token+".ipa")
	os.WriteFile(dummyPath, []byte{}, 0644)

	manifestURL := h.BaseURL + "/api/install/manifest/" + token
	installURL := "itms-services://?action=download-manifest&url=" + manifestURL

	log.Printf("注册本地安装 manifest: token=%s, port=%d, bundle=%s", token, req.LocalPort, req.BundleID)

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data": gin.H{
			"token":       token,
			"install_url": installURL,
		},
	})
}

// RemoteSign 接收原始 IPA + 签名选项，服务端用 zsign 签名后返回安装链接
// POST /api/install/sign
func (h *InstallHandler) RemoteSign(c *gin.Context) {
	file, err := c.FormFile("ipa")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "缺少 IPA 文件"})
		return
	}

	userID := c.GetInt64("user_id")
	bundleID := c.PostForm("bundle_id")
	appName := c.PostForm("app_name")

	// 获取用户的证书
	certs, err := h.CertRepo.FindByUserID(userID)
	if err != nil || len(certs) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "未找到有效证书，请先购买证书"})
		return
	}
	cert := certs[0]
	if cert.Status != "active" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "证书已过期"})
		return
	}

	// 获取设备 UDID
	var deviceUDID string
	if cert.DeviceID > 0 && h.DeviceRepo != nil {
		devices, _ := h.DeviceRepo.FindByUserID(userID)
		if len(devices) > 0 {
			deviceUDID = devices[0].UDID
		}
	}
	if deviceUDID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "找不到设备 UDID"})
		return
	}

	// 从内测侠获取证书文件
	p12Data, mpData, err := h.queryCertFromNeicexia(deviceUDID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "获取证书文件失败"})
		return
	}

	// 保存到一次性隔离目录（签完自动清理）
	token := "sign_" + uuid.New().String()
	tmpDir, err := os.MkdirTemp(h.IPADir, "sign-")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "创建临时目录失败"})
		return
	}
	defer os.RemoveAll(tmpDir)

	p12Path := filepath.Join(tmpDir, "cert.p12")
	mpPath := filepath.Join(tmpDir, "cert.mobileprovision")
	inputIPA := filepath.Join(tmpDir, "input.ipa")
	os.WriteFile(p12Path, p12Data, 0600)
	os.WriteFile(mpPath, mpData, 0600)

	// 保存上传的 IPA
	if err := c.SaveUploadedFile(file, inputIPA); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "保存 IPA 失败"})
		return
	}

	// 从原始 IPA 提取 bundle ID 和 App 名称（签名前，确保 manifest.plist 信息正确）
	if bundleID == "" || appName == "" {
		extractedBundleID, extractedAppName := extractIPAMetadata(inputIPA)
		if bundleID == "" && extractedBundleID != "" {
			bundleID = extractedBundleID
			log.Printf("从 IPA 提取 bundleID: %s", bundleID)
		}
		if appName == "" && extractedAppName != "" {
			appName = extractedAppName
			log.Printf("从 IPA 提取 appName: %s", appName)
		}
	}

	// 用 zsign 签名
	signedDir := filepath.Join(h.IPADir, "signed")
	os.MkdirAll(signedDir, 0755)
	outputIPA := filepath.Join(signedDir, token+".ipa")

	args := []string{
		"-k", p12Path,
		"-p", "1",
		"-m", mpPath,
		"-o", outputIPA,
	}
	if bundleID != "" {
		args = append(args, "-b", bundleID)
	}
	if appName != "" {
		args = append(args, "-n", appName)
	}
	args = append(args, inputIPA)

	cmd := exec.Command("zsign", args...)
	output, err := cmd.CombinedOutput()
	if err != nil {
		log.Printf("远程签名失败: %v, output: %s", err, string(output))
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "签名失败"})
		return
	}

	// 保存元数据（使用提取到的真实 bundleID 和 appName）
	metaJSON := fmt.Sprintf(`{"bundle_id":"%s","app_name":"%s"}`, bundleID, appName)
	os.WriteFile(filepath.Join(signedDir, token+".json"), []byte(metaJSON), 0644)

	installURL := "itms-services://?action=download-manifest&url=" + h.BaseURL + "/api/install/manifest/" + token
	log.Printf("远程签名完成: token=%s, size=%d", token, file.Size)

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data": gin.H{
			"token":       token,
			"install_url": installURL,
		},
	})
}

// UploadSigned 接收客户端上传的已签名 IPA，返回安装链接
// POST /api/install/upload
func (h *InstallHandler) UploadSigned(c *gin.Context) {
	file, err := c.FormFile("ipa")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "缺少 IPA 文件"})
		return
	}

	// 读取元数据
	bundleID := c.PostForm("bundle_id")
	appName := c.PostForm("app_name")
	if bundleID == "" {
		bundleID = "com.app.signed"
	}
	if appName == "" {
		appName = "签名应用"
	}

	// 生成唯一 token（不可预测）
	token := "upload_" + uuid.New().String()

	// 保存到 signed 目录
	signedDir := filepath.Join(h.IPADir, "signed")
	os.MkdirAll(signedDir, 0755)
	destPath := filepath.Join(signedDir, token+".ipa")

	if err := c.SaveUploadedFile(file, destPath); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "保存文件失败"})
		return
	}

	// 保存元数据（用于生成 manifest）
	metaPath := filepath.Join(signedDir, token+".json")
	metaJSON := fmt.Sprintf(`{"bundle_id":"%s","app_name":"%s"}`, bundleID, appName)
	os.WriteFile(metaPath, []byte(metaJSON), 0644)

	log.Printf("上传签名 IPA: token=%s, size=%d, bundle=%s", token, file.Size, bundleID)

	installURL := "itms-services://?action=download-manifest&url=" + h.BaseURL + "/api/install/manifest/" + token

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data": gin.H{
			"token":       token,
			"install_url": installURL,
		},
	})
}

// extractIPAMetadata 从 IPA 文件中提取 bundle ID 和 App 名称
func extractIPAMetadata(ipaPath string) (bundleID string, appName string) {
	// 尝试用 plistutil 转换 binary plist 为 XML（Linux 服务器）
	// unzip -p 直接从 IPA 中读取 Info.plist 到 stdout
	extractCmd := exec.Command("unzip", "-p", ipaPath, "Payload/*/Info.plist")
	plistData, err := extractCmd.Output()
	if err != nil || len(plistData) == 0 {
		log.Printf("从 IPA 提取 Info.plist 失败: %v", err)
		return "", ""
	}

	// 尝试用 plistutil 将 binary plist 转为 XML
	plistutilCmd := exec.Command("plistutil", "-i", "/dev/stdin", "-o", "/dev/stdout", "-f", "xml")
	plistutilCmd.Stdin = strings.NewReader(string(plistData))
	xmlData, err := plistutilCmd.Output()
	if err != nil {
		// plistutil 不可用，尝试直接当 XML 解析
		log.Printf("plistutil 转换失败，尝试直接解析 XML: %v", err)
		xmlData = plistData
	}

	xmlStr := string(xmlData)
	bundleID = extractXMLPlistValue(xmlStr, "CFBundleIdentifier")
	appName = extractXMLPlistValue(xmlStr, "CFBundleDisplayName")
	if appName == "" {
		appName = extractXMLPlistValue(xmlStr, "CFBundleName")
	}
	return bundleID, appName
}

// extractXMLPlistValue 从 XML plist 中提取指定 key 的 string 值
func extractXMLPlistValue(plist string, key string) string {
	pattern := "<key>" + key + "</key>"
	idx := strings.Index(plist, pattern)
	if idx < 0 {
		return ""
	}
	rest := plist[idx+len(pattern):]
	rest = strings.TrimSpace(rest)
	if !strings.HasPrefix(rest, "<string>") {
		return ""
	}
	rest = rest[len("<string>"):]
	end := strings.Index(rest, "</string>")
	if end < 0 {
		return ""
	}
	return rest[:end]
}

// queryCertFromNeicexia 从内测侠查询证书文件
func (h *InstallHandler) queryCertFromNeicexia(udid string) (p12 []byte, mp []byte, err error) {
	params := url.Values{}
	params.Set("udid", udid)
	params.Set("skip_processing_udid", "0")
	params.Set("token", h.NeicexiaToken)

	resp, err := http.PostForm("https://www.neicexia.com/public_service/query_cer", params)
	if err != nil {
		return nil, nil, fmt.Errorf("请求内测侠失败: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, nil, fmt.Errorf("读取响应失败: %w", err)
	}

	var result struct {
		IsSuccess bool   `json:"IsSuccess"`
		ErrorMsg  string `json:"ErrorMessage"`
		Data      struct {
			P12FileData             string `json:"p12_file_date"`
			MobileProvisionFileData string `json:"mobile_provision_file_data"`
		} `json:"Data"`
	}

	if err := json.Unmarshal(body, &result); err != nil {
		return nil, nil, fmt.Errorf("解析响应失败: %w", err)
	}

	if !result.IsSuccess {
		return nil, nil, fmt.Errorf("内测侠返回失败: %s", result.ErrorMsg)
	}

	p12, err = base64.StdEncoding.DecodeString(result.Data.P12FileData)
	if err != nil {
		return nil, nil, fmt.Errorf("P12 base64 解码失败: %w", err)
	}

	mp, err = base64.StdEncoding.DecodeString(result.Data.MobileProvisionFileData)
	if err != nil {
		return nil, nil, fmt.Errorf("mobileprovision base64 解码失败: %w", err)
	}

	return p12, mp, nil
}
