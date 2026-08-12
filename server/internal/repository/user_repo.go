package repository

import (
	"database/sql"
	"fmt"

	"github.com/haifeng/jisign-server/internal/model"
)

// UserRepo 用户数据库操作
type UserRepo struct {
	DB *sql.DB
}

// NewUserRepo 创建用户仓库
func NewUserRepo(db *sql.DB) *UserRepo {
	return &UserRepo{DB: db}
}

// FindByPhone 根据手机号查找用户
func (r *UserRepo) FindByPhone(phone string) (*model.User, error) {
	var user model.User
	err := r.DB.QueryRow(
		`SELECT id, phone, nickname, avatar_url, created_at, updated_at
		 FROM users WHERE phone = $1`, phone,
	).Scan(&user.ID, &user.Phone, &user.Nickname, &user.AvatarURL, &user.CreatedAt, &user.UpdatedAt)

	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("查询用户失败: %w", err)
	}
	return &user, nil
}

// FindByID 根据 ID 查找用户
func (r *UserRepo) FindByID(id int64) (*model.User, error) {
	var user model.User
	err := r.DB.QueryRow(
		`SELECT id, phone, nickname, avatar_url, created_at, updated_at
		 FROM users WHERE id = $1`, id,
	).Scan(&user.ID, &user.Phone, &user.Nickname, &user.AvatarURL, &user.CreatedAt, &user.UpdatedAt)

	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("查询用户失败: %w", err)
	}
	return &user, nil
}

// Create 创建用户，返回新用户（含自增 ID）
func (r *UserRepo) Create(phone string) (*model.User, error) {
	var user model.User
	err := r.DB.QueryRow(
		`INSERT INTO users (phone) VALUES ($1)
		 RETURNING id, phone, nickname, avatar_url, created_at, updated_at`, phone,
	).Scan(&user.ID, &user.Phone, &user.Nickname, &user.AvatarURL, &user.CreatedAt, &user.UpdatedAt)

	if err != nil {
		return nil, fmt.Errorf("创建用户失败: %w", err)
	}
	return &user, nil
}
