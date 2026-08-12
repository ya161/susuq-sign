-- 暂存匿名 UDID（UDID 在登录前获取的场景）
-- 登录后迁移到 devices 表并删除此记录

CREATE TABLE IF NOT EXISTS pending_devices (
    id          BIGSERIAL PRIMARY KEY,
    udid        VARCHAR(100) UNIQUE NOT NULL,
    model       VARCHAR(50) DEFAULT '',
    ios_version VARCHAR(20) DEFAULT '',
    created_at  TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_pending_devices_udid ON pending_devices(udid);
