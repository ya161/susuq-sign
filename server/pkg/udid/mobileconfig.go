package udid

import (
	"bytes"
	"encoding/xml"
	"fmt"
	"text/template"
)

const mobileconfigTemplate = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>PayloadContent</key>
    <dict>
        <key>URL</key>
        <string>{{.CallbackURL}}</string>
        <key>DeviceAttributes</key>
        <array>
            <string>UDID</string>
            <string>IMEI</string>
            <string>ICCID</string>
            <string>VERSION</string>
            <string>PRODUCT</string>
            <string>SERIAL</string>
        </array>
    </dict>
    <key>PayloadOrganization</key>
    <string>速签 SuSign</string>
    <key>PayloadDisplayName</key>
    <string>获取设备 UDID</string>
    <key>PayloadVersion</key>
    <integer>1</integer>
    <key>PayloadUUID</key>
    <string>{{.PayloadUUID}}</string>
    <key>PayloadIdentifier</key>
    <string>com.susuq.udid</string>
    <key>PayloadDescription</key>
    <string>此描述文件用于获取您的设备标识符(UDID)，获取后将自动删除。</string>
    <key>PayloadType</key>
    <string>Profile Service</string>
</dict>
</plist>`

type MobileConfigParams struct {
	CallbackURL string
	PayloadUUID string
}

// GenerateMobileConfig 生成 UDID 收集用的 mobileconfig 描述文件
// 注意：callbackURL 里可能包含 `&`（多参数拼接），必须 XML 转义后再嵌入，
// 否则 iOS 会把整个 plist 当非法 XML 拒绝（"无效的描述文件"）
func GenerateMobileConfig(callbackURL string, payloadUUID string) ([]byte, error) {
	tmpl, err := template.New("mobileconfig").Parse(mobileconfigTemplate)
	if err != nil {
		return nil, fmt.Errorf("解析模板失败: %w", err)
	}

	var buf bytes.Buffer
	params := MobileConfigParams{
		CallbackURL: xmlEscape(callbackURL),
		PayloadUUID: xmlEscape(payloadUUID),
	}
	if err := tmpl.Execute(&buf, params); err != nil {
		return nil, fmt.Errorf("生成配置文件失败: %w", err)
	}

	return buf.Bytes(), nil
}

// xmlEscape 将 `& < > " '` 等字符转义为 XML 实体
func xmlEscape(s string) string {
	var buf bytes.Buffer
	_ = xml.EscapeText(&buf, []byte(s))
	return buf.String()
}
