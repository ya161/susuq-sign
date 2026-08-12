"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState, useEffect } from "react";
import { Menu, X } from "lucide-react";
import { isLoggedIn, getUser, logout } from "@/lib/auth";

export function Navbar() {
  const pathname = usePathname();
  const [loggedIn, setLoggedIn] = useState(false);
  const [phone, setPhone] = useState("");
  const [menuOpen, setMenuOpen] = useState(false);

  useEffect(() => {
    setLoggedIn(isLoggedIn());
    const user = getUser();
    if (user) {
      // 手机号脱敏：138****1234
      setPhone(
        user.phone.slice(0, 3) + "****" + user.phone.slice(7)
      );
    }
  }, []);

  const handleLogout = () => {
    logout();
    setLoggedIn(false);
    setPhone("");
    setMenuOpen(false);
  };

  const navLinks = [
    { href: "/", label: "首页" },
    { href: "/install", label: "安装" },
    { href: "/purchase", label: "购买证书" },
    { href: "/cert-download", label: "下载证书" },
  ];

  return (
    <nav className="sticky top-0 z-50 backdrop-blur-xl bg-background/80 border-b border-card-border">
      <div className="max-w-5xl mx-auto px-4 h-14 flex items-center justify-between">
        {/* Logo */}
        <Link href="/" className="flex items-center gap-2">
          <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-blue-500 to-cyan-500 flex items-center justify-center text-white font-bold text-sm">
            速
          </div>
          <span className="font-semibold text-lg">速签</span>
        </Link>

        {/* 桌面端导航 */}
        <div className="hidden sm:flex items-center gap-6">
          {navLinks.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              className={`text-sm transition-colors ${
                pathname === link.href
                  ? "text-primary-light font-medium"
                  : "text-text-secondary hover:text-white"
              }`}
            >
              {link.label}
            </Link>
          ))}
          {loggedIn ? (
            <div className="flex items-center gap-3">
              <span className="text-sm text-text-secondary">{phone}</span>
              <button
                onClick={handleLogout}
                className="text-sm text-text-secondary hover:text-white transition-colors"
              >
                退出
              </button>
            </div>
          ) : null}
        </div>

        {/* 移动端菜单按钮 */}
        <button
          onClick={() => setMenuOpen(!menuOpen)}
          className="sm:hidden p-2 text-text-secondary"
        >
          {menuOpen ? <X size={20} /> : <Menu size={20} />}
        </button>
      </div>

      {/* 移动端展开菜单 */}
      {menuOpen && (
        <div className="sm:hidden border-t border-card-border bg-background px-4 py-3 space-y-3">
          {navLinks.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              onClick={() => setMenuOpen(false)}
              className={`block text-sm py-1 ${
                pathname === link.href
                  ? "text-primary-light font-medium"
                  : "text-text-secondary"
              }`}
            >
              {link.label}
            </Link>
          ))}
          {loggedIn && (
            <>
              <div className="text-sm text-text-secondary">{phone}</div>
              <button
                onClick={handleLogout}
                className="text-sm text-text-secondary"
              >
                退出登录
              </button>
            </>
          )}
        </div>
      )}
    </nav>
  );
}
