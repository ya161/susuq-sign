"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import {
  Phone,
  KeyRound,
  Fingerprint,
  CreditCard,
  Download,
  Check,
  Loader2,
  ChevronRight,
  AlertCircle,
  ExternalLink,
  Copy,
} from "lucide-react";
import {
  sendSmsCode,
  login,
  getUdidConfigUrl,
  getUdidSign,
  checkUdid,
  purchaseCert,
  createAlipayOrder,
  generateCert,
  getCertList,
  getCertPrice,
  getOrders,
  getInstallUrl,
  type CertItem,
} from "@/lib/api";
import { saveAuth, isLoggedIn, getUser } from "@/lib/auth";

const PENDING_ORDER_KEY = "susuq_pending_order_no";

// 当前步骤枚举
type Step = 1 | 2 | 3 | 4;

// 步骤配置（UDID → 登录 → 支付 → 安装）
const steps = [
  { step: 1 as Step, icon: Fingerprint, label: "获取 UDID" },
  { step: 2 as Step, icon: Phone, label: "登录" },
  { step: 3 as Step, icon: CreditCard, label: "支付" },
  { step: 4 as Step, icon: Download, label: "安装" },
];

export default function PurchasePage() {
  const [currentStep, setCurrentStep] = useState<Step>(1);

  // Step 1: 获取 UDID 状态
  const [udid, setUdid] = useState("");
  const [manualUdid, setManualUdid] = useState("");
  const [showManualInput, setShowManualInput] = useState(false);
  const pollingRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // Step 2: 登录状态
  const [phoneNumber, setPhoneNumber] = useState("");
  const [smsCode, setSmsCode] = useState("");
  const [countdown, setCountdown] = useState(0);
  const [userId, setUserId] = useState("");

  // Step 3: 支付状态
  const [orderNo, setOrderNo] = useState("");
  const [batchNo, setBatchNo] = useState("");
  const orderPollingRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // UDID 签名令牌（登录后拉取）
  const [udidSig, setUdidSig] = useState("");

  // 证书价格（从后端拉取）
  const [price, setPrice] = useState<number | null>(null);

  // 通用状态
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [copied, setCopied] = useState(false);

  // 拉取证书价格（公开接口，每次进页面刷新最新价）
  useEffect(() => {
    getCertPrice("personal_cert")
      .then((res) => {
        if (res.success && res.data) setPrice(res.data.amount);
      })
      .catch(() => {
        /* 价格拉取失败不阻塞购买 */
      });
  }, []);

  // 检查登录状态 + 支付回调 + UDID
  useEffect(() => {
    // 检查 URL 参数：支付完成回调 ?paid=订单号 或 UDID 回调 ?udid=xxx
    const params = new URLSearchParams(window.location.search);
    const paidOrderNo = params.get("paid");
    const urlUdid = params.get("udid");

    // 如果 URL 中有 UDID（从匿名回调带回），保存并停留在步骤1显示
    if (urlUdid && !udid) {
      setUdid(urlUdid);
      // 停留在步骤1，让用户看到 UDID 并手动点"下一步"
      // 清理 URL 参数
      window.history.replaceState({}, "", "/purchase/");
      return;
    }
    const pendingOrderNo =
      paidOrderNo || localStorage.getItem(PENDING_ORDER_KEY) || "";

    if (pendingOrderNo && isLoggedIn()) {
      // 支付回调恢复流程
      const user = getUser();
      if (user) {
        setUserId(user.user_id);
        getUdidSign().then((res) => {
          if (res.success && res.data?.sig) setUdidSig(res.data.sig);
        });
      }

      setOrderNo(pendingOrderNo);
      setCurrentStep(3);
      setLoading(true);

      (async () => {
        try {
          const ordersRes = await getOrders();
          const order = ordersRes.data?.find((o) => o.order_no === pendingOrderNo);
          if (!order) {
            localStorage.removeItem(PENDING_ORDER_KEY);
            setCurrentStep(1);
            return;
          }

          if (order.payment_status !== "paid") {
            setCurrentStep(3);
            startOrderPolling(pendingOrderNo);
            return;
          }

          // 已支付 → 获取 UDID 并生成证书
          const deviceUdid = order.udid || udid || "";
          if (deviceUdid) setUdid(deviceUdid);

          const certRes = await generateCert(pendingOrderNo, deviceUdid);
          if (certRes.success && certRes.data) {
            setBatchNo(certRes.data.udid_batch_no);
            localStorage.removeItem(PENDING_ORDER_KEY);
            setCurrentStep(4);
          } else {
            setError(certRes.error || "证书生成失败，请联系客服");
          }
        } catch {
          setError("恢复订单失败，请刷新重试");
        } finally {
          setLoading(false);
          if (paidOrderNo) {
            window.history.replaceState({}, "", "/purchase/");
          }
        }
      })();
      return;
    }

    if (isLoggedIn()) {
      const user = getUser();
      if (user) {
        setUserId(user.user_id);
        getUdidSign().then((res) => {
          if (res.success && res.data?.sig) setUdidSig(res.data.sig);
        });

        // 已登录 → 检查是否有证书或 UDID，跳到对应步骤
        getCertList().then(async (certRes) => {
          const activeCert = certRes.data?.find((c: CertItem) => c.status === "active");
          if (activeCert) {
            setBatchNo(activeCert.udid_batch_no);
            const sigRes = await getUdidSign();
            const sig = sigRes.data?.sig || "";
            const udidRes = await checkUdid(user.user_id, sig);
            if (udidRes.data?.udid) setUdid(udidRes.data.udid);
            setCurrentStep(4);
            return;
          }
          // 无证书 → 回到 UDID 步骤
          setCurrentStep(1);
        }).catch(() => {
          setCurrentStep(1);
        });
        return;
      }
    }

    // 未登录 → 从步骤 1（获取 UDID）开始
    setCurrentStep(1);
  }, []);

  // 清理轮询
  useEffect(() => {
    return () => {
      if (pollingRef.current) clearInterval(pollingRef.current);
      if (orderPollingRef.current) clearInterval(orderPollingRef.current);
    };
  }, []);

  // 验证码倒计时
  useEffect(() => {
    if (countdown <= 0) return;
    const timer = setTimeout(() => setCountdown(countdown - 1), 1000);
    return () => clearTimeout(timer);
  }, [countdown]);

  // ========== Step 1: 登录 ==========

  const handleSendCode = async () => {
    if (!phoneNumber || phoneNumber.length !== 11) {
      setError("请输入正确的手机号");
      return;
    }
    setError("");
    setLoading(true);
    try {
      const res = await sendSmsCode(phoneNumber);
      if (res.success) {
        setCountdown(60);
      } else {
        setError(res.error || "发送验证码失败");
      }
    } catch {
      setError("网络错误，请重试");
    } finally {
      setLoading(false);
    }
  };

  const handleLogin = async () => {
    if (!smsCode) {
      setError("请输入验证码");
      return;
    }
    setError("");
    setLoading(true);
    try {
      const res = await login(phoneNumber, smsCode);
      if (res.success && res.data) {
        saveAuth(res.data.token, {
          user_id: String(res.data.user.id),
          phone: res.data.user.phone,
        });
        setUserId(String(res.data.user.id));

        // 获取 UDID 签名令牌
        const sigRes = await getUdidSign();
        if (sigRes.success && sigRes.data?.sig) setUdidSig(sigRes.data.sig);

        // 登录成功 → 已有 UDID，直接进入支付
        if (udid) {
          setCurrentStep(3);
        } else {
          // 没有 UDID，回到步骤 1
          setCurrentStep(1);
        }
      } else {
        setError(res.error || "登录失败");
      }
    } catch {
      setError("网络错误，请重试");
    } finally {
      setLoading(false);
    }
  };

  // ========== Step 1: 获取 UDID ==========

  const startUdidPolling = useCallback(() => {
    if (pollingRef.current) clearInterval(pollingRef.current);
    pollingRef.current = setInterval(async () => {
      try {
        // 匿名查询（user_id=0），不依赖登录
        const res = await checkUdid("0");
        if (res.success && res.data?.found && res.data?.udid) {
          setUdid(res.data.udid);
          if (pollingRef.current) clearInterval(pollingRef.current);
          // UDID 获取成功，进入下一步（登录）
          setCurrentStep(2);
        }
      } catch {
        // 静默重试
      }
    }, 3000);
  }, []);

  const handleGetUdid = () => {
    // 匿名获取 UDID（user_id=0，无需登录）
    window.location.href = getUdidConfigUrl("0");
    // 开始轮询
    startUdidPolling();
  };

  const handleManualUdid = () => {
    if (!manualUdid || manualUdid.length < 20) {
      setError("请输入正确的 UDID");
      return;
    }
    setError("");
    setUdid(manualUdid);
    setCurrentStep(2); // UDID 获取成功 → 进入登录
  };

  // ========== Step 3: 支付 ==========

  /// 轮询订单状态：先查支付状态，再拉证书
  const startOrderPolling = useCallback((orderNumber: string) => {
    if (orderPollingRef.current) clearInterval(orderPollingRef.current);
    let attempts = 0;
    orderPollingRef.current = setInterval(async () => {
      attempts++;
      if (attempts > 100) { // 5 分钟超时
        if (orderPollingRef.current) clearInterval(orderPollingRef.current);
        setError("支付超时，请刷新页面重试");
        return;
      }
      try {
        // 1. 先查订单状态
        const ordersRes = await getOrders();
        const order = ordersRes.data?.find((o) => o.order_no === orderNumber);
        if (!order || order.payment_status !== "paid") return;

        // 2. 已支付 → 拉证书（后端幂等）
        const certUdid = udid || order.udid;
        const res = await generateCert(orderNumber, certUdid);
        if (res.success && res.data) {
          if (orderPollingRef.current) clearInterval(orderPollingRef.current);
          setBatchNo(res.data.udid_batch_no);
          localStorage.removeItem(PENDING_ORDER_KEY);
          setCurrentStep(4);
        }
      } catch {
        // 静默重试
      }
    }, 3000);
  }, [udid]);

  const handlePurchase = async () => {
    setError("");
    setLoading(true);
    try {
      // 创建订单
      const purchaseRes = await purchaseCert(udid);
      if (!purchaseRes.success || !purchaseRes.data) {
        setError(purchaseRes.error || "创建订单失败");
        setLoading(false);
        return;
      }

      const newOrderNo = purchaseRes.data.order_no;
      setOrderNo(newOrderNo);

      // 获取支付链接
      const payRes = await createAlipayOrder(newOrderNo);
      if (!payRes.success || !payRes.data) {
        setError(payRes.error || "创建支付失败");
        setLoading(false);
        return;
      }

      // 持久化 pending orderNo：跳转支付宝后页面会卸载，回来要能恢复
      localStorage.setItem(PENDING_ORDER_KEY, newOrderNo);

      // 先启动轮询（sessionStorage 里临时）— 然后跳转支付宝
      startOrderPolling(newOrderNo);

      window.location.href = payRes.data.payment_url;
    } catch {
      setError("网络错误，请重试");
    } finally {
      setLoading(false);
    }
  };

  // ========== Step 4: 安装 ==========

  const handleInstall = () => {
    window.location.href = getInstallUrl(batchNo);
  };

  // ========== 隐藏部分 UDID ==========
  const maskUdid = (u: string) => {
    if (u.length <= 8) return u;
    return u.slice(0, 4) + "****" + u.slice(-4);
  };

  return (
    <div className="px-4 py-8 max-w-lg mx-auto">
      <h1 className="text-2xl font-bold text-center mb-8">购买证书</h1>

      {/* 步骤指示器 */}
      <div className="flex items-center justify-between mb-10">
        {steps.map((s, idx) => (
          <div key={s.step} className="flex items-center">
            <div className="flex flex-col items-center">
              <div
                className={`w-10 h-10 rounded-full flex items-center justify-center transition-all ${
                  currentStep > s.step
                    ? "bg-green-500/20 text-green-400"
                    : currentStep === s.step
                    ? "bg-primary/20 text-primary-light ring-2 ring-primary/40"
                    : "bg-card-bg text-text-secondary"
                }`}
              >
                {currentStep > s.step ? (
                  <Check size={18} />
                ) : (
                  <s.icon size={18} />
                )}
              </div>
              <span
                className={`text-xs mt-1 ${
                  currentStep === s.step
                    ? "text-primary-light"
                    : "text-text-secondary"
                }`}
              >
                {s.label}
              </span>
            </div>
            {idx < steps.length - 1 && (
              <div
                className={`w-8 sm:w-12 h-px mx-1 mb-5 ${
                  currentStep > s.step ? "bg-green-500/40" : "bg-card-border"
                }`}
              />
            )}
          </div>
        ))}
      </div>

      {/* 错误提示 */}
      {error && (
        <div className="flex items-center gap-2 p-3 mb-4 rounded-xl bg-red-500/10 border border-red-500/20 text-red-400 text-sm">
          <AlertCircle size={16} />
          {error}
        </div>
      )}

      {/* Step 1: 获取 UDID（匿名，无需登录） */}
      {currentStep === 1 && (
        <div className="card space-y-4">
          <h2 className="text-lg font-semibold flex items-center gap-2">
            <Fingerprint size={20} className="text-primary-light" />
            获取设备 UDID
          </h2>

          {udid ? (
            <div className="space-y-3">
              <div className="flex items-center gap-2 text-green-400">
                <Check size={18} />
                <span className="text-sm">已获取 UDID</span>
              </div>
              <div className="bg-background rounded-lg p-3 font-mono text-sm text-text-secondary break-all">
                {udid}
              </div>
              <button
                onClick={() => {
                  navigator.clipboard.writeText(udid).then(() => {
                    setCopied(true);
                    setTimeout(() => setCopied(false), 2000);
                  });
                }}
                className={`w-full flex items-center justify-center gap-2 py-2 px-4 rounded-xl text-sm transition-colors ${
                  copied
                    ? "bg-green-500/20 text-green-400"
                    : "bg-card-bg hover:bg-card-bg/80 text-text-secondary"
                }`}
              >
                {copied ? (
                  <>
                    <Check size={16} />
                    已复制
                  </>
                ) : (
                  <>
                    <Copy size={16} />
                    复制 UDID
                  </>
                )}
              </button>
              <button
                onClick={() => setCurrentStep(2)}
                className="btn-primary w-full flex items-center justify-center gap-2"
              >
                下一步：登录
                <ChevronRight size={18} />
              </button>
            </div>
          ) : (
            <>
              <p className="text-sm text-text-secondary leading-relaxed">
                点击下方按钮，在 Safari 中安装描述文件以获取设备 UDID。
                无需登录，获取后自动进入下一步。
              </p>

              <button
                onClick={handleGetUdid}
                className="btn-primary w-full flex items-center justify-center gap-2"
              >
                <ExternalLink size={18} />
                安装描述文件获取 UDID
              </button>

              <div className="text-center">
                <button
                  onClick={() => setShowManualInput(!showManualInput)}
                  className="text-sm text-text-secondary hover:text-primary-light transition-colors"
                >
                  {showManualInput ? "关闭手动输入" : "手动输入 UDID"}
                </button>
              </div>

              {showManualInput && (
                <div className="space-y-3">
                  <input
                    type="text"
                    className="input font-mono text-sm"
                    placeholder="粘贴你的设备 UDID"
                    value={manualUdid}
                    onChange={(e) => setManualUdid(e.target.value.trim())}
                  />
                  <button
                    onClick={handleManualUdid}
                    className="btn-primary w-full text-sm"
                  >
                    确认 UDID
                  </button>
                </div>
              )}
            </>
          )}

          {!udid && (
            <div className="flex items-center gap-2 text-xs text-text-secondary/60">
              <Loader2 size={14} className="animate-spin" />
              等待获取 UDID...
            </div>
          )}
        </div>
      )}

      {/* Step 2: 登录 */}
      {currentStep === 2 && (
        <div className="card space-y-4">
          <h2 className="text-lg font-semibold flex items-center gap-2">
            <Phone size={20} className="text-primary-light" />
            手机号登录
          </h2>
          <p className="text-sm text-text-secondary">
            请输入手机号获取验证码登录
          </p>

          <div>
            <input
              type="tel"
              className="input"
              placeholder="请输入手机号"
              value={phoneNumber}
              onChange={(e) => setPhoneNumber(e.target.value.replace(/\D/g, "").slice(0, 11))}
              maxLength={11}
            />
          </div>

          <div className="flex gap-3">
            <input
              type="text"
              className="input flex-1"
              placeholder="验证码"
              value={smsCode}
              onChange={(e) => setSmsCode(e.target.value.replace(/\D/g, "").slice(0, 6))}
              maxLength={6}
            />
            <button
              onClick={handleSendCode}
              disabled={countdown > 0 || loading}
              className="btn-primary whitespace-nowrap text-sm px-4"
            >
              {countdown > 0 ? `${countdown}s` : "获取验证码"}
            </button>
          </div>

          <button
            onClick={handleLogin}
            disabled={loading || !phoneNumber || !smsCode}
            className="btn-primary w-full flex items-center justify-center gap-2"
          >
            {loading ? (
              <Loader2 size={18} className="animate-spin" />
            ) : (
              <>
                登录
                <ChevronRight size={18} />
              </>
            )}
          </button>
        </div>
      )}

      {/* Step 3: 支付 */}
      {currentStep === 3 && (
        <div className="card space-y-4">
          <h2 className="text-lg font-semibold flex items-center gap-2">
            <CreditCard size={20} className="text-primary-light" />
            确认支付
          </h2>

          <div className="bg-background rounded-xl p-4 space-y-3">
            <div className="flex justify-between items-center">
              <span className="text-text-secondary">商品</span>
              <span>个人开发者证书</span>
            </div>
            <div className="flex justify-between items-center">
              <span className="text-text-secondary">有效期</span>
              <span>1 年</span>
            </div>
            <div className="flex justify-between items-center">
              <span className="text-text-secondary">设备 UDID</span>
              <span className="font-mono text-sm">{maskUdid(udid)}</span>
            </div>
            <div className="border-t border-card-border pt-3 flex justify-between items-center">
              <span className="text-text-secondary">应付金额</span>
              <span className="text-2xl font-bold text-primary-light">
                {price != null ? `¥${price.toFixed(2)}` : "¥--"}
              </span>
            </div>
          </div>

          <button
            onClick={handlePurchase}
            disabled={loading}
            className="btn-primary w-full flex items-center justify-center gap-2 py-4"
          >
            {loading ? (
              <Loader2 size={18} className="animate-spin" />
            ) : (
              <>
                <CreditCard size={18} />
                支付宝支付
              </>
            )}
          </button>

          {orderNo && (
            <div className="flex items-center gap-2 text-xs text-text-secondary/60">
              <Loader2 size={14} className="animate-spin" />
              等待支付结果...
            </div>
          )}
        </div>
      )}

      {/* Step 4: 安装速签 App */}
      {currentStep === 4 && (
        <div className="card space-y-5 text-center">
          <div className="inline-flex items-center justify-center w-16 h-16 rounded-2xl bg-green-500/10 mx-auto">
            <Check size={32} className="text-green-400" />
          </div>

          <h2 className="text-xl font-semibold">证书已就绪！</h2>
          <p className="text-sm text-text-secondary">
            速签 App 已用你的证书签名，点击下方按钮安装
          </p>

          <button
            onClick={handleInstall}
            className="btn-primary w-full flex items-center justify-center gap-2 py-4 text-lg"
          >
            <Download size={20} />
            安装速签 App
          </button>

          {/* 安装指南 */}
          <div className="bg-background rounded-xl p-4 text-left space-y-3">
            <h3 className="text-sm font-medium flex items-center gap-2">
              <KeyRound size={14} className="text-primary-light" />
              安装后操作
            </h3>
            <ol className="text-sm text-text-secondary space-y-2 list-decimal list-inside leading-relaxed">
              <li>点击安装后，在弹窗中选择「安装」</li>
              <li>前往「设置 → 通用 → VPN与设备管理」</li>
              <li>找到开发者证书并点击「信任」</li>
              <li>返回桌面，打开速签 App 即可使用</li>
            </ol>
          </div>

          {/* 证书信息 */}
          <div className="bg-background rounded-xl p-4 text-left space-y-2 text-sm">
            <div className="flex justify-between">
              <span className="text-text-secondary">证书批次</span>
              <span className="font-mono text-xs">{batchNo}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-text-secondary">绑定设备</span>
              <span className="font-mono text-xs">{maskUdid(udid)}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-text-secondary">有效期</span>
              <span>约 1 年</span>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
