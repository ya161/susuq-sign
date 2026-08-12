"use client";

import { useState } from "react";
import {
  Download,
  Loader2,
  Check,
  AlertCircle,
  Copy,
  Key,
  Smartphone,
} from "lucide-react";

type CertType = {
  value: number;
  label: string;
  description: string;
};

const CERT_TYPES: CertType[] = [
  { value: 1, label: "标准版", description: "适合普通用户，性价比高" },
  { value: 2, label: "加强版", description: "更稳定，有效期更长" },
  { value: 3, label: "稳定版", description: "最稳定，适合长期使用" },
];

export default function CertDownloadPage() {
  const [udid, setUdid] = useState("");
  const [certType, setCertType] = useState(1);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [result, setResult] = useState<{
    cert_id: string;
    p12_base64: string;
    mobileprovision_base64: string;
    state: boolean;
  } | null>(null);
  const [copied, setCopied] = useState<"p12" | "mp" | null>(null);

  const handleDownload = async () => {
    if (!udid || udid.length < 20) {
      setError("请输入正确的 UDID（40位字符）");
      return;
    }

    setError("");
    setLoading(true);
    setResult(null);

    try {
      const response = await fetch("/api/cert/download-yiqian", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ udid, cert_type: certType }),
      });

      const data = await response.json();

      if (!data.success) {
        setError(data.error || "证书生成失败");
        return;
      }

      setResult(data.data);
    } catch {
      setError("网络错误，请重试");
    } finally {
      setLoading(false);
    }
  };

  const handleDownloadFile = (type: "p12" | "mobileprovision") => {
    if (!result) return;

    const base64Data = type === "p12" ? result.p12_base64 : result.mobileprovision_base64;
    const fileName = type === "p12"
      ? `certificate_${result.cert_id}.p12`
      : `certificate_${result.cert_id}.mobileprovision`;

    // 解码 base64 并下载
    const binaryString = atob(base64Data);
    const bytes = new Uint8Array(binaryString.length);
    for (let i = 0; i < binaryString.length; i++) {
      bytes[i] = binaryString.charCodeAt(i);
    }

    const blob = new Blob([bytes], { type: "application/octet-stream" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = fileName;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  };

  const copyToClipboard = (text: string, type: "p12" | "mp") => {
    navigator.clipboard.writeText(text).then(() => {
      setCopied(type);
      setTimeout(() => setCopied(null), 2000);
    });
  };

  return (
    <div className="px-4 py-8 max-w-lg mx-auto">
      <h1 className="text-2xl font-bold text-center mb-2">证书下载中心</h1>
      <p className="text-center text-text-secondary text-sm mb-8">
        输入设备 UDID，获取 P12 证书和描述文件
      </p>

      {/* 错误提示 */}
      {error && (
        <div className="flex items-center gap-2 p-3 mb-4 rounded-xl bg-red-500/10 border border-red-500/20 text-red-400 text-sm">
          <AlertCircle size={16} />
          {error}
        </div>
      )}

      {/* 输入表单 */}
      {!result && (
        <div className="card space-y-4">
          <div>
            <label className="block text-sm font-medium mb-2 flex items-center gap-2">
              <Smartphone size={16} className="text-primary-light" />
              设备 UDID
            </label>
            <input
              type="text"
              className="input font-mono text-sm"
              placeholder="请输入 40 位 UDID"
              value={udid}
              onChange={(e) => setUdid(e.target.value.trim())}
              maxLength={40}
            />
            <p className="text-xs text-text-secondary/60 mt-1">
              通过设置 → 通用 → 关于本机 → UDID 获取
            </p>
          </div>

          <div>
            <label className="block text-sm font-medium mb-2 flex items-center gap-2">
              <Key size={16} className="text-primary-light" />
              证书类型
            </label>
            <div className="space-y-2">
              {CERT_TYPES.map((cert) => (
                <label
                  key={cert.value}
                  className={`flex items-center p-3 rounded-xl border cursor-pointer transition-all ${
                    certType === cert.value
                      ? "border-primary bg-primary/10"
                      : "border-card-border hover:border-primary/50"
                  }`}
                >
                  <input
                    type="radio"
                    name="cert_type"
                    value={cert.value}
                    checked={certType === cert.value}
                    onChange={(e) => setCertType(Number(e.target.value))}
                    className="mr-3"
                  />
                  <div>
                    <div className="font-medium">{cert.label}</div>
                    <div className="text-xs text-text-secondary">
                      {cert.description}
                    </div>
                  </div>
                </label>
              ))}
            </div>
          </div>

          <button
            onClick={handleDownload}
            disabled={loading || !udid}
            className="btn-primary w-full flex items-center justify-center gap-2 py-3"
          >
            {loading ? (
              <>
                <Loader2 size={18} className="animate-spin" />
                生成中...
              </>
            ) : (
              <>
                <Download size={18} />
                生成证书
              </>
            )}
          </button>
        </div>
      )}

      {/* 结果展示 */}
      {result && (
        <div className="space-y-4">
          {/* 成功提示 */}
          <div className="card bg-green-500/10 border-green-500/20">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-full bg-green-500/20 flex items-center justify-center">
                <Check size={20} className="text-green-400" />
              </div>
              <div>
                <h3 className="font-medium text-green-400">证书生成成功！</h3>
                <p className="text-sm text-text-secondary">
                  证书ID: {result.cert_id}
                </p>
              </div>
            </div>
          </div>

          {/* P12 证书 */}
          <div className="card space-y-3">
            <h3 className="font-medium flex items-center gap-2">
              <Key size={16} className="text-primary-light" />
              P12 证书文件
            </h3>
            <p className="text-sm text-text-secondary">
              包含私钥和证书，用于签名 IPA 文件
            </p>
            <div className="flex gap-2">
              <button
                onClick={() => handleDownloadFile("p12")}
                className="btn-primary flex-1 flex items-center justify-center gap-2"
              >
                <Download size={16} />
                下载 .p12 文件
              </button>
              <button
                onClick={() => copyToClipboard(result.p12_base64, "p12")}
                className={`px-4 py-2 rounded-xl transition-colors ${
                  copied === "p12"
                    ? "bg-green-500/20 text-green-400"
                    : "bg-card-bg hover:bg-card-bg/80 text-text-secondary"
                }`}
              >
                {copied === "p12" ? <Check size={16} /> : <Copy size={16} />}
              </button>
            </div>
          </div>

          {/* MobileProvision */}
          <div className="card space-y-3">
            <h3 className="font-medium flex items-center gap-2">
              <Smartphone size={16} className="text-primary-light" />
              描述文件
            </h3>
            <p className="text-sm text-text-secondary">
              配置文件，包含设备授权信息
            </p>
            <div className="flex gap-2">
              <button
                onClick={() => handleDownloadFile("mobileprovision")}
                className="btn-primary flex-1 flex items-center justify-center gap-2"
              >
                <Download size={16} />
                下载 .mobileprovision 文件
              </button>
              <button
                onClick={() =>
                  copyToClipboard(result.mobileprovision_base64, "mp")
                }
                className={`px-4 py-2 rounded-xl transition-colors ${
                  copied === "mp"
                    ? "bg-green-500/20 text-green-400"
                    : "bg-card-bg hover:bg-card-bg/80 text-text-secondary"
                }`}
              >
                {copied === "mp" ? <Check size={16} /> : <Copy size={16} />}
              </button>
            </div>
          </div>

          {/* 使用说明 */}
          <div className="card space-y-3">
            <h3 className="font-medium">使用说明</h3>
            <ol className="text-sm text-text-secondary space-y-2 list-decimal list-inside leading-relaxed">
              <li>下载上面两个文件</li>
              <li>打开速签 App 或访问速签网站</li>
              <li>导入 P12 证书和描述文件</li>
              <li>选择要签名的 IPA 文件</li>
              <li>点击签名，等待完成</li>
            </ol>
          </div>

          {/* 重新生成 */}
          <button
            onClick={() => {
              setResult(null);
              setUdid("");
            }}
            className="w-full py-3 rounded-xl bg-card-bg hover:bg-card-bg/80 text-text-secondary transition-colors"
          >
            重新生成
          </button>
        </div>
      )}
    </div>
  );
}
