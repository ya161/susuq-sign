package repository

import (
	"database/sql"
	"fmt"
	"time"

	"github.com/haifeng/jisign-server/internal/model"
)

// OrderRepo 订单数据库操作
type OrderRepo struct {
	DB *sql.DB
}

// NewOrderRepo 创建订单仓库
func NewOrderRepo(db *sql.DB) *OrderRepo {
	return &OrderRepo{DB: db}
}

// Create 创建订单
func (r *OrderRepo) Create(order *model.Order) error {
	err := r.DB.QueryRow(
		`INSERT INTO orders (user_id, order_no, product_type, amount, udid, payment_method, payment_status)
		 VALUES ($1, $2, $3, $4, $5, $6, $7)
		 RETURNING id, created_at`,
		order.UserID, order.OrderNo, order.ProductType, order.Amount, order.UDID, order.PaymentMethod, order.PaymentStatus,
	).Scan(&order.ID, &order.CreatedAt)

	if err != nil {
		return fmt.Errorf("创建订单失败: %w", err)
	}
	return nil
}

// FindByUserID 获取用户的所有订单
func (r *OrderRepo) FindByUserID(userID int64) ([]model.Order, error) {
	rows, err := r.DB.Query(
		`SELECT id, user_id, order_no, product_type, amount, udid, payment_method, payment_status, paid_at, created_at
		 FROM orders WHERE user_id = $1 ORDER BY created_at DESC`, userID,
	)
	if err != nil {
		return nil, fmt.Errorf("查询订单列表失败: %w", err)
	}
	defer rows.Close()

	var orders []model.Order
	for rows.Next() {
		var o model.Order
		if err := rows.Scan(&o.ID, &o.UserID, &o.OrderNo, &o.ProductType, &o.Amount, &o.UDID,
			&o.PaymentMethod, &o.PaymentStatus, &o.PaidAt, &o.CreatedAt); err != nil {
			return nil, fmt.Errorf("扫描订单数据失败: %w", err)
		}
		orders = append(orders, o)
	}
	return orders, rows.Err()
}

// FindByOrderNo 根据订单号查找订单
func (r *OrderRepo) FindByOrderNo(orderNo string) (*model.Order, error) {
	var o model.Order
	err := r.DB.QueryRow(
		`SELECT id, user_id, order_no, product_type, amount, udid, payment_method, payment_status, paid_at, created_at
		 FROM orders WHERE order_no = $1`, orderNo,
	).Scan(&o.ID, &o.UserID, &o.OrderNo, &o.ProductType, &o.Amount, &o.UDID,
		&o.PaymentMethod, &o.PaymentStatus, &o.PaidAt, &o.CreatedAt)

	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("查询订单失败: %w", err)
	}
	return &o, nil
}

// FindByID 根据 ID 查找订单
func (r *OrderRepo) FindByID(id int64) (*model.Order, error) {
	var o model.Order
	err := r.DB.QueryRow(
		`SELECT id, user_id, order_no, product_type, amount, udid, payment_method, payment_status, paid_at, created_at
		 FROM orders WHERE id = $1`, id,
	).Scan(&o.ID, &o.UserID, &o.OrderNo, &o.ProductType, &o.Amount, &o.UDID,
		&o.PaymentMethod, &o.PaymentStatus, &o.PaidAt, &o.CreatedAt)

	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("查询订单失败: %w", err)
	}
	return &o, nil
}

// UpdatePaymentStatus 更新支付状态
func (r *OrderRepo) UpdatePaymentStatus(orderNo string, status string) error {
	var paidAt *time.Time
	if status == "paid" {
		now := time.Now()
		paidAt = &now
	}

	result, err := r.DB.Exec(
		`UPDATE orders SET payment_status = $1, paid_at = $2 WHERE order_no = $3`,
		status, paidAt, orderNo,
	)
	if err != nil {
		return fmt.Errorf("更新支付状态失败: %w", err)
	}

	rows, _ := result.RowsAffected()
	if rows == 0 {
		return fmt.Errorf("订单不存在: %s", orderNo)
	}
	return nil
}
