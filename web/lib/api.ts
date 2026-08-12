// 速签 API 客户端
// 后端地址：https://api.susuq.top
// 后端响应格式：{ success: boolean, data?: T, error?: string }

const API_BASE = "https://api.susuq.top";

// 后端统一响应格式
interface ApiResponse<T = unknown> {
  success: boolean;
  data?: T;
  error?: string;
}

async function request<T>(
  path: string,
  options: RequestInit = {}
): Promise<ApiResponse<T>> {
  const token =
    typeof window !== "undefined" ? localStorage.getItem("susuq_token") : null;

  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    ...((options.headers as Record<string, string>) || {}),
  };

  if (token) {
    headers["Authorization"] = `Bearer ${token}`;
  }

  const res = await fetch(`${API_BASE}${path}`, {
    ...options,
    headers,
  });

  const json = await res.json();
  return json as ApiResponse<T>;
}

// ========== 认证相关 ==========

// 发送短信验证码
export interface SmsCodeData {
  message: string;
  debugCode?: string;
}

export async function sendSmsCode(phone: string) {
  return request<SmsCodeData>("/api/auth/sms-code", {
    method: "POST",
    body: JSON.stringify({ phone }),
  });
}

// 验证码登录
export interface LoginData {
  token: string;
  user: {
    id: number;
    phone: string;
    nickname: string;
  };
}

export async function login(phone: string, code: string) {
  return request<LoginData>("/api/auth/login", {
    method: "POST",
    body: JSON.stringify({ phone, code }),
  });
}

// ========== UDID 相关 ==========

// 登录用户从后端获取 UDID 签名令牌，之后 config/check 都用它
export interface UdidSignData {
  sig: string;
  config_url: string;
}

export async function getUdidSign() {
  return request<UdidSignData>("/api/udid/sign");
}

// 获取 UDID 配置描述文件地址（登录用户带 sig）
export function getUdidConfigUrl(userId: string, sig?: string): string {
  const base = `${API_BASE}/api/udid/config?user_id=${userId}`;
  return sig ? `${base}&sig=${sig}` : base;
}

// 检查 UDID 是否已获取
export interface UdidCheckData {
  found: boolean;
  udid?: string;
}

export async function checkUdid(userId: string, sig?: string) {
  const suffix = sig ? `&sig=${sig}` : "";
  return request<UdidCheckData>(
    `/api/udid/check?user_id=${userId}${suffix}`
  );
}

// ========== 证书价格 ==========

export interface CertPriceData {
  product_type: string;
  amount: number;
  currency: string;
}

export async function getCertPrice(productType = "personal_cert") {
  return request<CertPriceData>(`/api/cert/price?product_type=${productType}`);
}

// ========== 证书购买 ==========

export interface PurchaseData {
  order_no: string;
  amount: number;
  product_type?: string;
}

export async function purchaseCert(udid: string) {
  return request<PurchaseData>("/api/cert/purchase", {
    method: "POST",
    body: JSON.stringify({
      udid,
      product_type: "personal_cert",
      payment_method: "alipay",
    }),
  });
}

// ========== 支付相关 ==========

export interface AlipayPayData {
  payment_url: string;
  order_no: string;
  amount: number;
}

export async function createAlipayOrder(orderNo: string) {
  return request<AlipayPayData>("/api/pay/alipay/create", {
    method: "POST",
    body: JSON.stringify({ order_no: orderNo }),
  });
}

// 查询订单列表（检查支付状态）
export interface OrderItem {
  id: number;
  order_no: string;
  product_type: string;
  amount: number;
  udid: string;
  payment_status: string;
  created_at: string;
}

export async function getOrders() {
  return request<OrderItem[]>("/api/orders");
}

// 查询用户的证书列表
export interface CertItem {
  id: number;
  udid_batch_no: string;
  status: string;
  pool_type: string;
}

export async function getCertList() {
  return request<CertItem[]>("/api/cert/list");
}

// 生成证书
export interface CertGenData {
  p12_data: string;
  mobileprovision_data: string;
  udid_batch_no: string;
}

export async function generateCert(orderNo: string, udid: string) {
  return request<CertGenData>("/api/cert/generate", {
    method: "POST",
    body: JSON.stringify({ order_no: orderNo, udid }),
  });
}

// ========== 安装相关 ==========

// 获取 App 安装 manifest 地址
export function getInstallUrl(batchNo: string): string {
  return `itms-services://?action=download-manifest&url=${encodeURIComponent(
    `${API_BASE}/api/install/manifest/${batchNo}`
  )}`;
}
