import Link from "next/link";
import {
  PenTool,
  ShieldCheck,
  Copy,
  Puzzle,
  ChevronRight,
  Zap,
  Smartphone,
  Lock,
  ArrowRight,
  Download,
  Star,
  Key,
} from "lucide-react";

const features = [
  { icon: PenTool, title: "一键签名", desc: "导入 IPA 即可签名安装，无需电脑" },
  { icon: ShieldCheck, title: "证书商城", desc: "¥69/年，即买即用，无限次签" },
  { icon: Copy, title: "应用多开", desc: "微信、抖音等应用多开分身" },
  { icon: Puzzle, title: "插件注入", desc: "dylib 注入，扩展应用功能" },
  { icon: Download, title: "证书下载", desc: "已有证书？直接下载 P12 文件" },
];

const steps = [
  { num: "01", title: "购买证书", desc: "支付宝一键购买个人开发者证书", color: "from-blue-500 to-cyan-600" },
  { num: "02", title: "安装速签", desc: "证书自动签名速签 App 并安装到设备", color: "from-cyan-500 to-teal-600" },
  { num: "03", title: "导入 IPA", desc: "通过软件源、浏览器或文件导入 IPA", color: "from-teal-500 to-emerald-600" },
  { num: "04", title: "签名使用", desc: "一键签名安装，支持多开和插件注入", color: "from-emerald-500 to-green-600" },
];

const brands = ["微信", "QQ", "抖音", "快手", "小红书", "Telegram", "WhatsApp", "Instagram"];

export default function HomePage() {
  return (
    <div className="relative overflow-hidden">
      {/* ===== 全局背景装饰 ===== */}
      <div className="fixed inset-0 pointer-events-none">
        <div className="absolute inset-0 bg-grid opacity-30" />
        {/* 浮动光球 */}
        <div className="absolute top-[10%] left-[15%] w-[500px] h-[500px] rounded-full bg-purple-600/8 blur-[150px] animate-float" />
        <div className="absolute top-[40%] right-[10%] w-[400px] h-[400px] rounded-full bg-indigo-500/6 blur-[130px] animate-float" style={{ animationDelay: "-3s" }} />
        <div className="absolute bottom-[10%] left-[30%] w-[600px] h-[600px] rounded-full bg-violet-600/5 blur-[160px] animate-float" style={{ animationDelay: "-1.5s" }} />
      </div>

      {/* ===== Hero ===== */}
      <section className="relative min-h-screen flex items-center justify-center px-4">
        {/* Hero 顶部渐变光 */}
        <div className="absolute top-0 left-1/2 -translate-x-1/2 w-[900px] h-[500px] bg-gradient-to-b from-purple-600/15 via-purple-600/5 to-transparent rounded-full blur-[80px]" />

        <div className="relative text-center max-w-4xl mx-auto">
          {/* 标签 */}
          <div className="animate-fade-rise inline-flex items-center gap-2 px-4 py-2 rounded-full liquid-glass mb-8 text-sm text-text-secondary">
            <Star size={14} className="text-yellow-400" />
            <span>iOS 签名工具 · 10,000+ 用户信赖</span>
          </div>

          {/* 主标题 */}
          <h1 className="animate-fade-rise-d1 text-6xl sm:text-8xl font-extrabold mb-6 tracking-tight leading-none">
            <span className="text-gradient bg-gradient-to-r from-blue-400 to-cyan-400 bg-clip-text text-transparent">速签</span>
          </h1>

          {/* 动态渐变副标题 */}
          <p className="animate-fade-rise-d2 text-2xl sm:text-3xl font-light mb-6" style={{ color: "rgba(255,255,255,0.7)" }}>
            签名，从未如此简单
          </p>

          <p className="animate-fade-rise-d2 text-base max-w-xl mx-auto mb-12 leading-relaxed" style={{ color: "rgba(255,255,255,0.4)" }}>
            一站式 iOS IPA 签名工具。购买证书 → 安装速签 → 导入 IPA → 一键签名。
            支持多开分身、插件注入，无需越狱，安全稳定。
          </p>

          {/* CTA 按钮 */}
          <div className="animate-fade-rise-d3 flex flex-col sm:flex-row items-center justify-center gap-4">
            <Link href="/install/" className="btn-primary inline-flex items-center gap-3 text-lg px-10 py-5 shadow-2xl shadow-blue-600/20 bg-gradient-to-r from-blue-500 to-cyan-500 hover:from-blue-600 hover:to-cyan-600">
              <Download size={22} />
              安装速签 App
            </Link>
            <Link href="/purchase/" className="btn-secondary inline-flex items-center gap-2 px-8 py-5 border-blue-500/30 hover:bg-blue-500/10">
              购买证书 ¥69/年
              <ArrowRight size={18} />
            </Link>
            <Link href="/cert-download/" className="btn-secondary inline-flex items-center gap-2 px-8 py-5 border-green-500/30 hover:bg-green-500/10">
              <Key size={18} />
              下载证书
            </Link>
          </div>

          {/* 信任指标 */}
          <div className="animate-fade-rise-d4 mt-16 flex items-center justify-center gap-8 sm:gap-12 text-sm" style={{ color: "rgba(255,255,255,0.3)" }}>
            <div className="text-center">
              <div className="text-2xl font-bold text-gradient-accent">99.9%</div>
              <div>签名成功率</div>
            </div>
            <div className="w-px h-8 bg-white/10" />
            <div className="text-center">
              <div className="text-2xl font-bold text-gradient-accent">&lt; 3s</div>
              <div>签名速度</div>
            </div>
            <div className="w-px h-8 bg-white/10" />
            <div className="text-center">
              <div className="text-2xl font-bold text-gradient-accent">iOS 15+</div>
              <div>系统支持</div>
            </div>
          </div>
        </div>

        {/* 底部渐变过渡 */}
        <div className="absolute bottom-0 left-0 right-0 h-32 bg-gradient-to-t from-background to-transparent" />
      </section>

      {/* ===== 应用支持跑马灯 ===== */}
      <section className="relative py-12 overflow-hidden border-y border-white/5">
        <div className="flex animate-marquee whitespace-nowrap">
          {[...brands, ...brands].map((name, i) => (
            <span key={i} className="mx-8 text-lg font-medium" style={{ color: "rgba(255,255,255,0.12)" }}>
              {name}
            </span>
          ))}
        </div>
      </section>

      {/* ===== 功能特性 ===== */}
      <section className="relative py-24 px-4">
        <div className="max-w-5xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-5xl font-bold mb-4 text-gradient bg-gradient-to-r from-blue-400 to-cyan-400 bg-clip-text text-transparent">为什么选择速签</h2>
            <p className="text-text-secondary text-lg">强大的功能，极简的体验</p>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-5">
            {features.map((feature) => (
              <div key={feature.title} className="group relative">
                <div className="card glow-border h-full">
                  <div className="flex items-start gap-5">
                    <div className="shrink-0 w-14 h-14 rounded-2xl bg-gradient-to-br from-primary/20 to-primary/5 flex items-center justify-center group-hover:from-primary/30 group-hover:to-primary/10 transition-all duration-500">
                      <feature.icon size={26} className="text-primary-light" />
                    </div>
                    <div>
                      <h3 className="text-xl font-semibold mb-2 group-hover:text-primary-light transition-colors">{feature.title}</h3>
                      <p className="text-text-secondary leading-relaxed">{feature.desc}</p>
                    </div>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* ===== 使用流程 ===== */}
      <section className="relative py-24 px-4">
        <div className="absolute inset-0 bg-radial-glow-bottom pointer-events-none" />
        <div className="max-w-4xl mx-auto relative">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-5xl font-bold mb-4 text-gradient">四步开始</h2>
            <p className="text-text-secondary text-lg">从购买到签名，全程不到 5 分钟</p>
          </div>

          <div className="space-y-5">
            {steps.map((step, i) => (
              <div key={step.num} className="liquid-glass rounded-2xl p-6 sm:p-8 flex items-start gap-6 group hover:bg-white/[0.03] transition-all">
                <div className={`shrink-0 w-16 h-16 rounded-2xl bg-gradient-to-br ${step.color} flex items-center justify-center shadow-lg`}>
                  <span className="text-white text-xl font-bold">{step.num}</span>
                </div>
                <div className="pt-1">
                  <h3 className="text-xl font-semibold mb-1 group-hover:text-primary-light transition-colors">{step.title}</h3>
                  <p className="text-text-secondary">{step.desc}</p>
                </div>
                <ChevronRight size={20} className="shrink-0 ml-auto mt-5 text-white/10 group-hover:text-primary-light/50 transition-colors" />
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* ===== 安全 + 信任 ===== */}
      <section className="relative py-24 px-4">
        <div className="max-w-4xl mx-auto">
          <div className="liquid-glass-strong liquid-glass rounded-3xl p-10 sm:p-16">
            <div className="text-center mb-12">
              <h2 className="text-3xl font-bold mb-3">安全可靠</h2>
              <p className="text-text-secondary">你的数据安全，是我们的第一优先级</p>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-10">
              <div className="text-center">
                <div className="w-16 h-16 rounded-2xl bg-primary/10 flex items-center justify-center mx-auto mb-4">
                  <Lock size={28} className="text-primary-light" />
                </div>
                <h3 className="font-semibold mb-2">Apple 官方签名</h3>
                <p className="text-sm text-text-secondary">使用苹果官方签名机制，证书来源可靠</p>
              </div>
              <div className="text-center">
                <div className="w-16 h-16 rounded-2xl bg-primary/10 flex items-center justify-center mx-auto mb-4">
                  <Zap size={28} className="text-primary-light" />
                </div>
                <h3 className="font-semibold mb-2">本地签名</h3>
                <p className="text-sm text-text-secondary">IPA 签名在你的设备上完成，不上传到服务器</p>
              </div>
              <div className="text-center">
                <div className="w-16 h-16 rounded-2xl bg-primary/10 flex items-center justify-center mx-auto mb-4">
                  <Smartphone size={28} className="text-primary-light" />
                </div>
                <h3 className="font-semibold mb-2">不越狱</h3>
                <p className="text-sm text-text-secondary">无需越狱设备，不影响保修和系统安全</p>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* ===== 底部 CTA ===== */}
      <section className="relative py-32 px-4">
        <div className="absolute inset-0 bg-radial-glow pointer-events-none" />
        <div className="max-w-2xl mx-auto text-center relative">
          <h2 className="text-4xl sm:text-5xl font-bold mb-6 text-gradient bg-gradient-to-r from-blue-400 to-cyan-400 bg-clip-text text-transparent">
            开始签名之旅
          </h2>
          <p className="text-xl text-text-secondary mb-12">
            加入 10,000+ 用户，体验最简单的 iOS 签名工具
          </p>
          <Link href="/install/" className="btn-primary inline-flex items-center gap-3 text-xl px-14 py-6 shadow-2xl shadow-blue-600/25 bg-gradient-to-r from-blue-500 to-cyan-500 hover:from-blue-600 hover:to-cyan-600">
            <Download size={24} />
            安装速签
          </Link>
        </div>
      </section>
    </div>
  );
}
