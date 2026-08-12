package repository

import (
	"database/sql"
	"fmt"

	"github.com/haifeng/jisign-server/internal/model"
)

// CertRepo 证书数据库操作
type CertRepo struct {
	DB *sql.DB
}

// NewCertRepo 创建证书仓库
func NewCertRepo(db *sql.DB) *CertRepo {
	return &CertRepo{DB: db}
}

// FindByUserID 获取用户的所有证书
func (r *CertRepo) FindByUserID(userID int64) ([]model.Certificate, error) {
	rows, err := r.DB.Query(
		`SELECT id, user_id, device_id, udid_batch_no, cer_appleid, pool_type, status, expire_at, created_at
		 FROM certificates WHERE user_id = $1 ORDER BY created_at DESC`, userID,
	)
	if err != nil {
		return nil, fmt.Errorf("查询证书列表失败: %w", err)
	}
	defer rows.Close()

	var certs []model.Certificate
	for rows.Next() {
		var c model.Certificate
		if err := rows.Scan(&c.ID, &c.UserID, &c.DeviceID, &c.UDIDBatchNo, &c.CerAppleID,
			&c.PoolType, &c.Status, &c.ExpireAt, &c.CreatedAt); err != nil {
			return nil, fmt.Errorf("扫描证书数据失败: %w", err)
		}
		certs = append(certs, c)
	}
	return certs, rows.Err()
}

// Save 保存证书记录
func (r *CertRepo) Save(cert *model.Certificate) error {
	err := r.DB.QueryRow(
		`INSERT INTO certificates (user_id, device_id, udid_batch_no, cer_appleid, pool_type, status, expire_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7)
		 RETURNING id, created_at`,
		cert.UserID, cert.DeviceID, cert.UDIDBatchNo, cert.CerAppleID, cert.PoolType, cert.Status, cert.ExpireAt,
	).Scan(&cert.ID, &cert.CreatedAt)

	if err != nil {
		return fmt.Errorf("保存证书失败: %w", err)
	}
	return nil
}

// UpdateStatus 更新证书状态
func (r *CertRepo) UpdateStatus(id int64, status string) error {
	result, err := r.DB.Exec(
		`UPDATE certificates SET status = $1 WHERE id = $2`, status, id,
	)
	if err != nil {
		return fmt.Errorf("更新证书状态失败: %w", err)
	}

	rows, _ := result.RowsAffected()
	if rows == 0 {
		return fmt.Errorf("证书不存在: id=%d", id)
	}
	return nil
}

// FindByBatchNo 根据批次号查找证书
func (r *CertRepo) FindByBatchNo(batchNo string) (*model.Certificate, error) {
	var c model.Certificate
	err := r.DB.QueryRow(
		`SELECT id, user_id, device_id, udid_batch_no, cer_appleid, pool_type, status, expire_at, created_at
		 FROM certificates WHERE udid_batch_no = $1`, batchNo,
	).Scan(&c.ID, &c.UserID, &c.DeviceID, &c.UDIDBatchNo, &c.CerAppleID,
		&c.PoolType, &c.Status, &c.ExpireAt, &c.CreatedAt)

	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("查询证书失败: %w", err)
	}
	return &c, nil
}

// FindActiveCerts 获取所有活跃证书（用于定时检查）
func (r *CertRepo) FindActiveCerts() ([]model.Certificate, error) {
	rows, err := r.DB.Query(
		`SELECT id, user_id, device_id, udid_batch_no, cer_appleid, pool_type, status, expire_at, created_at
		 FROM certificates WHERE status = 'active'`,
	)
	if err != nil {
		return nil, fmt.Errorf("查询活跃证书失败: %w", err)
	}
	defer rows.Close()

	var certs []model.Certificate
	for rows.Next() {
		var c model.Certificate
		if err := rows.Scan(&c.ID, &c.UserID, &c.DeviceID, &c.UDIDBatchNo, &c.CerAppleID,
			&c.PoolType, &c.Status, &c.ExpireAt, &c.CreatedAt); err != nil {
			return nil, fmt.Errorf("扫描证书数据失败: %w", err)
		}
		certs = append(certs, c)
	}
	return certs, rows.Err()
}
