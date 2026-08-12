package model

import "time"

// User 用户
type User struct {
	ID        int64     `json:"id" db:"id"`
	Phone     string    `json:"phone" db:"phone"`
	Nickname  string    `json:"nickname" db:"nickname"`
	AvatarURL string    `json:"avatar_url" db:"avatar_url"`
	CreatedAt time.Time `json:"created_at" db:"created_at"`
	UpdatedAt time.Time `json:"updated_at" db:"updated_at"`
}

// Device 设备
type Device struct {
	ID         int64     `json:"id" db:"id"`
	UserID     int64     `json:"user_id" db:"user_id"`
	UDID       string    `json:"udid" db:"udid"`
	Model      string    `json:"model" db:"model"`
	IOSVersion string    `json:"ios_version" db:"ios_version"`
	CreatedAt  time.Time `json:"created_at" db:"created_at"`
}

// Certificate 证书
type Certificate struct {
	ID           int64      `json:"id" db:"id"`
	UserID       int64      `json:"user_id" db:"user_id"`
	DeviceID     int64      `json:"device_id" db:"device_id"`
	UDIDBatchNo  string     `json:"udid_batch_no" db:"udid_batch_no"`
	CerAppleID   string     `json:"cer_appleid" db:"cer_appleid"`
	PoolType     string     `json:"pool_type" db:"pool_type"` // public / private
	Status       string     `json:"status" db:"status"`       // active / expired / revoked
	ExpireAt     *time.Time `json:"expire_at" db:"expire_at"`
	CreatedAt    time.Time  `json:"created_at" db:"created_at"`
}

// Order 订单
type Order struct {
	ID            int64      `json:"id" db:"id"`
	UserID        int64      `json:"user_id" db:"user_id"`
	OrderNo       string     `json:"order_no" db:"order_no"`
	ProductType   string     `json:"product_type" db:"product_type"` // personal_cert / enterprise_cert
	Amount        float64    `json:"amount" db:"amount"`
	UDID          string     `json:"udid" db:"udid"`
	PaymentMethod string     `json:"payment_method" db:"payment_method"` // wechat / alipay
	PaymentStatus string     `json:"payment_status" db:"payment_status"` // pending / paid / refunded
	PaidAt        *time.Time `json:"paid_at" db:"paid_at"`
	CreatedAt     time.Time  `json:"created_at" db:"created_at"`
}

// SignRecord 签名记录
type SignRecord struct {
	ID            int64     `json:"id" db:"id"`
	UserID        int64     `json:"user_id" db:"user_id"`
	CertificateID int64     `json:"certificate_id" db:"certificate_id"`
	IPAName       string    `json:"ipa_name" db:"ipa_name"`
	BundleID      string    `json:"bundle_id" db:"bundle_id"`
	NewBundleID   string    `json:"new_bundle_id" db:"new_bundle_id"`
	NewAppName    string    `json:"new_app_name" db:"new_app_name"`
	SignedAt      time.Time `json:"signed_at" db:"signed_at"`
}
