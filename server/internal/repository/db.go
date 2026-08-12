package repository

import (
	"database/sql"
	"fmt"

	_ "github.com/lib/pq"
)

// DB 全局数据库连接
var DB *sql.DB

// InitDB 初始化 PostgreSQL 数据库连接
func InitDB(dsn string) (*sql.DB, error) {
	db, err := sql.Open("postgres", dsn)
	if err != nil {
		return nil, fmt.Errorf("打开数据库连接失败: %w", err)
	}

	// 测试连接
	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("数据库连接测试失败: %w", err)
	}

	// 连接池配置
	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(5)

	DB = db
	return db, nil
}
