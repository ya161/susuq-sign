export function Footer() {
  return (
    <footer className="border-t border-card-border py-8 px-4">
      <div className="max-w-5xl mx-auto text-center space-y-3">
        <div className="flex items-center justify-center gap-2">
          <div className="w-6 h-6 rounded-md bg-gradient-to-br from-blue-500 to-cyan-500 flex items-center justify-center text-white font-bold text-xs">
            速
          </div>
          <span className="font-medium">速签</span>
        </div>
        <p className="text-sm text-text-secondary">
          iOS 签名工具 · 快速签名 · 安全稳定
        </p>
        <p className="text-sm text-text-secondary">
          客服微信：susuq_support
        </p>
        {/* 备案信息 */}
        <div className="text-xs text-text-secondary/60 space-y-1">
          <p>
            <a
              href="https://beian.miit.gov.cn/"
              target="_blank"
              rel="noopener noreferrer"
              className="hover:text-text-primary transition-colors"
            >
              苏ICP备2026040109号
            </a>
          </p>
          <p>
            <a
              href="http://www.beian.gov.cn/portal/registerSystemInfo?recordcode=32011402012606"
              target="_blank"
              rel="noopener noreferrer"
              className="hover:text-text-primary transition-colors"
            >
              苏公网安备32011402012606号
            </a>
          </p>
        </div>
        <p className="text-xs text-text-secondary/60">
          © {new Date().getFullYear()} 速签 SuSign. All rights reserved.
        </p>
      </div>
    </footer>
  );
}
