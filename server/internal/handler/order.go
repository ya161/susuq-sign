package handler

import (
	"log"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/haifeng/jisign-server/internal/model"
	"github.com/haifeng/jisign-server/internal/repository"
)

// OrderHandler 订单管理处理
type OrderHandler struct {
	OrderRepo *repository.OrderRepo
}

// List 获取当前用户的订单列表
// GET /api/orders
func (h *OrderHandler) List(c *gin.Context) {
	userID := c.GetInt64("user_id")

	orders, err := h.OrderRepo.FindByUserID(userID)
	if err != nil {
		log.Printf("查询订单列表失败: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "查询订单列表失败"})
		return
	}

	// 确保返回空数组而非 null
	if orders == nil {
		orders = []model.Order{}
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    orders,
	})
}

// Detail 获取订单详情
// GET /api/orders/:id
func (h *OrderHandler) Detail(c *gin.Context) {
	userID := c.GetInt64("user_id")

	orderID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "无效的订单 ID"})
		return
	}

	order, err := h.OrderRepo.FindByID(orderID)
	if err != nil {
		log.Printf("查询订单详情失败: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "查询订单失败"})
		return
	}

	if order == nil || order.UserID != userID {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "订单不存在"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    order,
	})
}
