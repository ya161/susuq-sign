-- 极签数据库初始化
-- 执行: psql -d jisign -f 001_init.sql

CREATE TABLE IF NOT EXISTS users (
    id          BIGSERIAL PRIMARY KEY,
    phone       VARCHAR(20) UNIQUE NOT NULL,
    nickname    VARCHAR(50) DEFAULT '',
    avatar_url  TEXT DEFAULT '',
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    updated_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS devices (
    id          BIGSERIAL PRIMARY KEY,
    user_id     BIGINT REFERENCES users(id) ON DELETE CASCADE,
    udid        VARCHAR(100) UNIQUE NOT NULL,
    model       VARCHAR(50) DEFAULT '',
    ios_version VARCHAR(20) DEFAULT '',
    created_at  TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_devices_user_id ON devices(user_id);

CREATE TABLE IF NOT EXISTS certificates (
    id              BIGSERIAL PRIMARY KEY,
    user_id         BIGINT REFERENCES users(id) ON DELETE CASCADE,
    device_id       BIGINT REFERENCES devices(id) ON DELETE SET NULL,
    udid_batch_no   VARCHAR(20) NOT NULL,
    cer_appleid     VARCHAR(100) DEFAULT '',
    pool_type       VARCHAR(20) DEFAULT 'public',
    status          VARCHAR(20) DEFAULT 'active',
    expire_at       TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_certificates_user_id ON certificates(user_id);
CREATE INDEX idx_certificates_status ON certificates(status);

CREATE TABLE IF NOT EXISTS orders (
    id              BIGSERIAL PRIMARY KEY,
    user_id         BIGINT REFERENCES users(id) ON DELETE CASCADE,
    order_no        VARCHAR(50) UNIQUE NOT NULL,
    product_type    VARCHAR(30) NOT NULL,
    amount          DECIMAL(10,2) NOT NULL,
    udid            VARCHAR(100) DEFAULT '',
    payment_method  VARCHAR(20) DEFAULT '',
    payment_status  VARCHAR(20) DEFAULT 'pending',
    paid_at         TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_orders_user_id ON orders(user_id);
CREATE INDEX idx_orders_order_no ON orders(order_no);

CREATE TABLE IF NOT EXISTS sign_records (
    id              BIGSERIAL PRIMARY KEY,
    user_id         BIGINT REFERENCES users(id) ON DELETE CASCADE,
    certificate_id  BIGINT REFERENCES certificates(id) ON DELETE SET NULL,
    ipa_name        VARCHAR(100) DEFAULT '',
    bundle_id       VARCHAR(200) DEFAULT '',
    new_bundle_id   VARCHAR(200) DEFAULT '',
    new_app_name    VARCHAR(100) DEFAULT '',
    signed_at       TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_sign_records_user_id ON sign_records(user_id);
