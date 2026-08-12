package repository

import (
	"database/sql"
	"fmt"

	"github.com/haifeng/jisign-server/internal/model"
)

// DeviceRepo 设备数据库操作
type DeviceRepo struct {
	DB *sql.DB
}

// NewDeviceRepo 创建设备仓库
func NewDeviceRepo(db *sql.DB) *DeviceRepo {
	return &DeviceRepo{DB: db}
}

// FindByUserID 获取用户的所有设备
func (r *DeviceRepo) FindByUserID(userID int64) ([]model.Device, error) {
	rows, err := r.DB.Query(
		`SELECT id, user_id, udid, model, ios_version, created_at
		 FROM devices WHERE user_id = $1 ORDER BY created_at DESC`, userID,
	)
	if err != nil {
		return nil, fmt.Errorf("查询设备列表失败: %w", err)
	}
	defer rows.Close()

	var devices []model.Device
	for rows.Next() {
		var d model.Device
		if err := rows.Scan(&d.ID, &d.UserID, &d.UDID, &d.Model, &d.IOSVersion, &d.CreatedAt); err != nil {
			return nil, fmt.Errorf("扫描设备数据失败: %w", err)
		}
		devices = append(devices, d)
	}
	return devices, rows.Err()
}

// FindByUDID 根据 UDID 查找设备
func (r *DeviceRepo) FindByUDID(udid string) (*model.Device, error) {
	var d model.Device
	err := r.DB.QueryRow(
		`SELECT id, user_id, udid, model, ios_version, created_at
		 FROM devices WHERE udid = $1`, udid,
	).Scan(&d.ID, &d.UserID, &d.UDID, &d.Model, &d.IOSVersion, &d.CreatedAt)

	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("查询设备失败: %w", err)
	}
	return &d, nil
}

// Save 保存设备（存在则更新元数据，不存在则插入）
// 冲突时禁止跨用户改绑：只有同一 user_id 或原记录 user_id 为 0 时才允许 UPDATE
func (r *DeviceRepo) Save(device *model.Device) error {
	err := r.DB.QueryRow(
		`INSERT INTO devices (user_id, udid, model, ios_version)
		 VALUES ($1, $2, $3, $4)
		 ON CONFLICT (udid) DO UPDATE SET
		   model = EXCLUDED.model,
		   ios_version = EXCLUDED.ios_version
		 WHERE devices.user_id = EXCLUDED.user_id OR devices.user_id = 0
		 RETURNING id, created_at`,
		device.UserID, device.UDID, device.Model, device.IOSVersion,
	).Scan(&device.ID, &device.CreatedAt)

	if err == sql.ErrNoRows {
		// WHERE 条件不满足：同一 UDID 已归属其他用户，拒绝改绑
		return fmt.Errorf("UDID 已归属其他账号，无法跨用户改绑")
	}
	if err != nil {
		return fmt.Errorf("保存设备失败: %w", err)
	}
	return nil
}

// Delete 删除设备（需验证归属用户）
func (r *DeviceRepo) Delete(id int64, userID int64) error {
	result, err := r.DB.Exec(
		`DELETE FROM devices WHERE id = $1 AND user_id = $2`, id, userID,
	)
	if err != nil {
		return fmt.Errorf("删除设备失败: %w", err)
	}

	rows, _ := result.RowsAffected()
	if rows == 0 {
		return fmt.Errorf("设备不存在或无权限删除")
	}
	return nil
}

// AssociateAnonymous 将匿名设备（user_id=0）关联到指定用户
// 登录后调用，把之前 UDID 匿名暂存的设备绑定到当前用户
func (r *DeviceRepo) AssociateAnonymous(userID int64) (int64, error) {
	result, err := r.DB.Exec(
		`UPDATE devices SET user_id = $1 WHERE user_id = 0`, userID,
	)
	if err != nil {
		return 0, fmt.Errorf("关联匿名设备失败: %w", err)
	}
	return result.RowsAffected()
}

// SaveAnonymous 保存匿名设备到 pending_devices 表（无外键约束）
// 用于 UDID 在登录前获取的场景
func (r *DeviceRepo) SaveAnonymous(device *model.Device) error {
	err := r.DB.QueryRow(
		`INSERT INTO pending_devices (udid, model, ios_version)
		 VALUES ($1, $2, $3)
		 ON CONFLICT (udid) DO UPDATE SET
		   model = EXCLUDED.model,
		   ios_version = EXCLUDED.ios_version
		 RETURNING id`,
		device.UDID, device.Model, device.IOSVersion,
	).Scan(&device.ID)

	if err != nil {
		return fmt.Errorf("保存匿名设备失败: %w", err)
	}
	return nil
}

// FindPending 查询最新的匿名暂存设备
func (r *DeviceRepo) FindPending() (*model.Device, error) {
	var d model.Device
	err := r.DB.QueryRow(
		`SELECT id, udid, model, ios_version, created_at
		 FROM pending_devices ORDER BY created_at DESC LIMIT 1`,
	).Scan(&d.ID, &d.UDID, &d.Model, &d.IOSVersion, &d.CreatedAt)

	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("查询匿名设备失败: %w", err)
	}
	return &d, nil
}

// MigratePending 将 pending_devices 中的匿名设备迁移到 devices 表
// 登录后调用，返回迁移数量
func (r *DeviceRepo) MigratePending(userID int64) (int64, error) {
	// 先插入到 devices（已存在的跳过）
	_, err := r.DB.Exec(
		`INSERT INTO devices (user_id, udid, model, ios_version)
		 SELECT $1, udid, model, ios_version FROM pending_devices
		 ON CONFLICT (udid) DO UPDATE SET
		   user_id = $1,
		   model = EXCLUDED.model,
		   ios_version = EXCLUDED.ios_version
		 WHERE devices.user_id = 0`, userID,
	)
	if err != nil {
		return 0, fmt.Errorf("迁移设备失败: %w", err)
	}

	// 删除已迁移的记录
	result, err := r.DB.Exec(
		`DELETE FROM pending_devices WHERE udid IN (SELECT udid FROM devices WHERE user_id = $1)`, userID,
	)
	if err != nil {
		return 0, fmt.Errorf("清理 pending 失败: %w", err)
	}
	return result.RowsAffected()
}
