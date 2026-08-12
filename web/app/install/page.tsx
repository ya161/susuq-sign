"use client";

import Link from "next/link";
import { useState } from "react";
import {
  Download,
  ShieldCheck,
  Key,
  ArrowRight,
  ChevronDown,
  ChevronUp,
  Smartphone,
  CheckCircle,
  AlertCircle,
  Apple,
} from "lucide-react";

export default function InstallPage() {
  const [showOwnCert, setShowOwnCert] = useState(false);
  const [showFAQ, setShowFAQ] = useState<number | null>(null);
  const [p12File, setP12File] = useState<File | null>(null);
  const [mpFile, setMpFile] = useState<File | null>(null);
  const [p12Password, setP12Password] = useState("");
  const [signing, setSigning] = useState(false);
  const [signResult, setSignResult] = useState<{ success: boolean; message: string; installUrl?: string } | null>(null);

  const handleSignWithCert = async () => {
    if (!p12File || !mpFile) {
      setSignResult({ success: false, message: "请选择 P12 证书文件和描述文件" });
      return;
    }

    setSigning(true);
    setSignResult(null);

    try {
      const formData = new FormData();
      formData.append("p12", p12File);
      formData.append("mobileprovision", mpFile);
      formData.append("p12_password", p12Password || "1");

      const res = await fetch("/api/install/sign-with-cert", {
        method: "POST",
        body: formData,
      });

      const data = await res.json();

      if (data.success && data.data?.install_url) {
        setSignResult({
          success: true,
          message: "签名成功！点击下方按钮安装",
          installUrl: data.data.install_url,
        });
        // 自动触发安装
        window.location.href = data.data.install_url;
      } else {
        setSignResult({
          success: false,
          message: data.error || "签名失败，请稍后重试",
        });
      }
    } catch (err) {
      setSignResult({ success: false, message: "网络错误，请稍后重试" });
    } finally {
      setSigning(false);
    }
  };

  const faqs = [
    {
      q: "什么是 UDID？为什么需要它？",
      a: "UDID 是每台 Apple 设备的唯一标识符。个人开发者证书需要绑定设备 UDID 才能签名安装应用。获取过程完全自动化，只需在 Safari 中安装一个描述文件即可。"
    },
    {
      q: "证书有效期多久？过期后怎么办？",
      a: "个人开发者证书有效期约 1 年。有效期内可无限次签名任意 IPA。过期后需要重新购买证书。我们会在过期前 7 天通知你。"
    },
    {
      q: "安装后需要做什么设置？",
      a: "安装完成后，需要前往「设置 → 通用 → VPN与设备管理」，找到对应的开发者证书并点击「信任」。之后即可正常使用速签 App。"
    },
    {
      q: "我已有证书（P12 + 描述文件），可以直接用吗？",
      a: "可以。在下方选择「我已有证书」，按照指引操作即可。你的证书将用于签名速签 App 本身以及后续签名其他 IPA。"
    },
  ];

  return (
    <div className="relative min-h-screen overflow-hidden">
      {/* 背景 */}
      <div className="fixed inset-0 pointer-events-none">
        <div className="absolute inset-0 bg-grid opacity-30" />
        <div className="absolute top-[20%] left-[20%] w-[500px] h-[500px] rounded-full bg-purple-600/8 blur-[150px] animate-float" />
        <div className="absolute bottom-[20%] right-[15%] w-[400px] h-[400px] rounded-full bg-indigo-500/6 blur-[130px] animate-float" style={{ animationDelay: "-2s" }} />
      </div>

      <div className="relative max-w-2xl mx-auto px-4 py-12 sm:py-20">
        {/* 标题 */}
        <div className="text-center mb-12 animate-fade-rise">
          <div className="inline-flex items-center justify-center w-20 h-20 rounded-3xl bg-gradient-to-br from-primary via-primary-light to-primary mb-6 shadow-2xl animate-pulse-glow">
            <Download size={36} className="text-white" />
          </div>
          <h1 className="text-3xl sm:text-4xl font-bold mb-3 text-gradient bg-gradient-to-r from-blue-400 to-cyan-400 bg-clip-text text-transparent">安装速签 App</h1>
          <p className="text-text-secondary text-lg">选择适合你的方式开始</p>
        </div>

        {/* ===== 选项 1：购买证书（推荐） ===== */}
        <div className="animate-fade-rise-d1 mb-6">
          <div className="liquid-glass rounded-2xl p-6 sm:p-8 border border-primary/20 relative overflow-hidden">
            {/* 推荐标签 */}
            <div className="absolute top-0 right-0 bg-gradient-to-l from-primary to-primary-light text-white text-xs font-semibold px-4 py-1.5 rounded-bl-xl">
              推荐
            </div>

            <div className="flex items-start gap-4 mb-6">
              <div className="shrink-0 w-12 h-12 rounded-xl bg-blue-500/15 flex items-center justify-center">
                <ShieldCheck size={24} className="text-blue-400" />
              </div>
              <div>
                <h2 className="text-xl font-semibold mb-1">购买证书 + 安装速签</h2>
                <p className="text-text-secondary text-sm">没有证书？一键购买并自动安装速签 App</p>
              </div>
            </div>

            {/* 权益列表 */}
            <div className="space-y-3 mb-6">
              {[
                "个人开发者证书，有效期约 1 年",
                "有效期内无限次签名任意 IPA",
                "自动签名并安装速签 App",
                "支持多开分身、插件注入、改名改图标",
                "证书过期前自动提醒",
              ].map((item) => (
                <div key={item} className="flex items-start gap-3">
                  <CheckCircle size={18} className="text-green-400 shrink-0 mt-0.5" />
                  <span className="text-sm" style={{ color: "rgba(255,255,255,0.7)" }}>{item}</span>
                </div>
              ))}
            </div>

            {/* 价格 + 购买按钮 */}
            <div className="flex items-center justify-between pt-4 border-t border-white/5">
              <div>
                <span className="text-3xl font-bold text-gradient bg-gradient-to-r from-blue-400 to-cyan-400 bg-clip-text text-transparent">¥69</span>
                <span className="text-text-secondary text-sm ml-2">/ 年</span>
              </div>
              <Link href="/purchase/" className="btn-primary inline-flex items-center gap-2 px-8 py-3.5 bg-gradient-to-r from-blue-500 to-cyan-500 hover:from-blue-600 hover:to-cyan-600">
                立即购买
                <ArrowRight size={18} />
              </Link>
            </div>
          </div>
        </div>

        {/* ===== 选项 2：已有证书 ===== */}
        <div className="animate-fade-rise-d2 mb-10">
          <button
            onClick={() => setShowOwnCert(!showOwnCert)}
            className="w-full liquid-glass rounded-2xl p-6 text-left hover:bg-white/[0.03] transition-all"
          >
            <div className="flex items-center justify-between">
              <div className="flex items-start gap-4">
                <div className="shrink-0 w-12 h-12 rounded-xl bg-white/5 flex items-center justify-center">
                  <Key size={24} className="text-text-secondary" />
                </div>
                <div>
                  <h2 className="text-lg font-semibold mb-1">我已有证书</h2>
                  <p className="text-text-secondary text-sm">有 P12 + mobileprovision？直接安装速签</p>
                </div>
              </div>
              {showOwnCert ? <ChevronUp size={20} className="text-text-secondary" /> : <ChevronDown size={20} className="text-text-secondary" />}
            </div>
          </button>

          {showOwnCert && (
            <div className="mt-3 liquid-glass rounded-2xl p-6 space-y-4">
              <div className="flex items-start gap-3 p-4 rounded-xl bg-amber-500/5 border border-amber-500/10">
                <AlertCircle size={18} className="text-amber-400 shrink-0 mt-0.5" />
                <p className="text-sm" style={{ color: "rgba(255,255,255,0.6)" }}>
                  你需要将证书文件（P12 + mobileprovision）通过我们的服务端签名速签 App。
                  上传的证书仅用于签名，不会被存储。
                </p>
              </div>

              <div className="space-y-3">
                <div>
                  <label className="text-sm text-text-secondary mb-2 block">P12 证书文件</label>
                  <input
                    type="file"
                    accept=".p12,.pfx"
                    className="input text-sm"
                    onChange={(e) => setP12File(e.target.files?.[0] || null)}
                  />
                </div>
                <div>
                  <label className="text-sm text-text-secondary mb-2 block">描述文件 (.mobileprovision)</label>
                  <input
                    type="file"
                    accept=".mobileprovision"
                    className="input text-sm"
                    onChange={(e) => setMpFile(e.target.files?.[0] || null)}
                  />
                </div>
                <div>
                  <label className="text-sm text-text-secondary mb-2 block">P12 密码</label>
                  <input
                    type="password"
                    placeholder="输入 P12 证书密码"
                    className="input"
                    value={p12Password}
                    onChange={(e) => setP12Password(e.target.value)}
                  />
                </div>
              </div>

              {signResult && (
                <div className={`p-4 rounded-xl ${signResult.success ? 'bg-green-500/10 border border-green-500/20' : 'bg-red-500/10 border border-red-500/20'}`}>
                  <p className={`text-sm ${signResult.success ? 'text-green-400' : 'text-red-400'}`}>
                    {signResult.message}
                  </p>
                  {signResult.installUrl && (
                    <a
                      href={signResult.installUrl}
                      className="mt-2 inline-block text-sm text-blue-400 hover:text-blue-300"
                    >
                      点击此处手动安装 →
                    </a>
                  )}
                </div>
              )}

              <button
                className="btn-primary w-full flex items-center justify-center gap-2 py-3.5"
                disabled={signing || !p12File || !mpFile}
                onClick={handleSignWithCert}
              >
                {signing ? (
                  <>
                    <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                    签名中...
                  </>
                ) : (
                  <>
                    <Download size={18} />
                    签名并安装速签 App
                  </>
                )}
              </button>
            </div>
          )}
        </div>


        {/* ===== 安装后操作指南 ===== */}
        <div className="animate-fade-rise-d3 mb-10">
          <h3 className="text-lg font-semibold mb-4 flex items-center gap-2">
            <Smartphone size={20} className="text-primary-light" />
            安装后操作
          </h3>
          <div className="space-y-3">
            {[
              { step: "1", text: "点击安装链接后，在弹窗中选择「安装」" },
              { step: "2", text: "前往「设置 → 通用 → VPN与设备管理」" },
              { step: "3", text: "找到开发者证书，点击「信任」" },
              { step: "4", text: "返回桌面，打开速签 App，开始签名" },
            ].map((item) => (
              <div key={item.step} className="flex items-start gap-4 p-4 rounded-xl bg-white/[0.02]">
                <div className="shrink-0 w-8 h-8 rounded-full bg-primary/15 flex items-center justify-center text-sm font-bold text-primary-light">
                  {item.step}
                </div>
                <p className="text-sm pt-1" style={{ color: "rgba(255,255,255,0.6)" }}>{item.text}</p>
              </div>
            ))}
          </div>
        </div>

        {/* ===== FAQ ===== */}
        <div className="animate-fade-rise-d4">
          <h3 className="text-lg font-semibold mb-4">常见问题</h3>
          <div className="space-y-2">
            {faqs.map((faq, i) => (
              <div key={i} className="liquid-glass rounded-xl overflow-hidden">
                <button
                  onClick={() => setShowFAQ(showFAQ === i ? null : i)}
                  className="w-full flex items-center justify-between p-4 text-left hover:bg-white/[0.02] transition-colors"
                >
                  <span className="text-sm font-medium pr-4">{faq.q}</span>
                  {showFAQ === i ?
                    <ChevronUp size={16} className="shrink-0 text-text-secondary" /> :
                    <ChevronDown size={16} className="shrink-0 text-text-secondary" />
                  }
                </button>
                {showFAQ === i && (
                  <div className="px-4 pb-4">
                    <p className="text-sm text-text-secondary leading-relaxed">{faq.a}</p>
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
