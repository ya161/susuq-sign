-- 自签功能数据库扩展
-- 执行: psql -d jisign -f 002_selfsign.sql

-- 自签会话（存储 Apple ID 认证信息）
CREATE TABLE IF NOT EXISTS selfsign_sessions (
    id              BIGSERIAL PRIMARY KEY,
    udid            VARCHAR(100) NOT NULL,
    apple_id        VARCHAR(255) NOT NULL,
    dsid            VARCHAR(255) DEFAULT '',
    auth_token      TEXT DEFAULT '',
    team_id         VARCHAR(32) DEFAULT '',
    private_key     BYTEA,              -- CSR 私钥（加密存储）
    cert_data       BYTEA,              -- 签名证书 DER
    cert_serial     VARCHAR(255) DEFAULT '',
    status          VARCHAR(32) DEFAULT 'pending',  -- pending / 2fa / active / expired
    expires_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_selfsign_sessions_udid ON selfsign_sessions(udid);
CREATE INDEX idx_selfsign_sessions_status ON selfsign_sessions(status);

-- 自签 App 记录（跟踪每个签名的 App 的 Bundle ID，用于续签）
CREATE TABLE IF NOT EXISTS selfsign_apps (
    id              BIGSERIAL PRIMARY KEY,
    session_id      BIGINT REFERENCES selfsign_sessions(id) ON DELETE CASCADE,
    bundle_id       VARCHAR(255) NOT NULL,
    app_name        VARCHAR(255) DEFAULT '',
    apple_app_id    VARCHAR(255) DEFAULT '',     -- Apple 注册的 App ID
    profile_data    BYTEA,                       -- 描述文件
    ipa_path        VARCHAR(512) DEFAULT '',
    expires_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_selfsign_apps_session ON selfsign_apps(session_id);
CREATE INDEX idx_selfsign_apps_bundle ON selfsign_apps(bundle_id);
