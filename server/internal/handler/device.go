package handler

import (
	"log"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/haifeng/jisign-server/internal/model"
	"github.com/haifeng/jisign-server/internal/repository"
)

// DeviceHandler 设备管理处理
type DeviceHandler struct {
	DeviceRepo *repository.DeviceRepo
}

// List 获取当前用户的设备列表
// GET /api/devices
func (h *DeviceHandler) List(c *gin.Context) {
	userID := c.GetInt64("user_id")

	devices, err := h.DeviceRepo.FindByUserID(userID)
	if err != nil {
		log.Printf("查询设备列表失败: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "查询设备列表失败"})
		return
	}

	// 确保返回空数组而非 null
	if devices == nil {
		devices = []model.Device{}
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    devices,
	})
}

// Delete 删除设备
// DELETE /api/devices/:id
func (h *DeviceHandler) Delete(c *gin.Context) {
	userID := c.GetInt64("user_id")

	deviceID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "无效的设备 ID"})
		return
	}

	if err := h.DeviceRepo.Delete(deviceID, userID); err != nil {
		log.Printf("删除设备失败: %v", err)
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    gin.H{"message": "设备已删除"},
	})
}
