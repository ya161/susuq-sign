#!/bin/bash
# 速签项目部署脚本
# Usage: ./deploy.sh

set -e

SERVER="root@8.155.23.131"
REMOTE_DIR="/opt/jisign"
LOCAL_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== 速签项目部署 ==="
echo "服务器: $SERVER"
echo "远程目录: $REMOTE_DIR"
echo ""

# 1. 同步服务器代码
echo "[1/5] 同步服务器代码..."
ssh $SERVER "cd $REMOTE_DIR && git pull origin main" 2>/dev/null || echo "  (git pull 跳过或失败)"

# 2. 上传编译好的服务器二进制文件
echo "[2/5] 上传服务器二进制文件..."
scp "$LOCAL_DIR/jisign-server-linux" "$SERVER:$REMOTE_DIR/server/jisign-server"

# 3. 上传 website 文件
echo "[3/5] 上传 website 文件..."
ssh $SERVER "rm -rf $REMOTE_DIR/website/*"
scp -r "$LOCAL_DIR/website/"* "$SERVER:$REMOTE_DIR/website/"

# 4. 更新 docker-compose.yml
echo "[4/5] 更新 docker-compose.yml..."
scp "$LOCAL_DIR/docker-compose.yml" "$SERVER:$REMOTE_DIR/docker-compose.yml"

# 5. 重启服务
echo "[5/5] 重启 Docker 服务..."
ssh $SERVER "cd $REMOTE_DIR && docker compose down && docker compose up -d"

echo ""
echo "=== 部署完成 ==="
echo "请检查服务状态: ssh $SERVER 'docker compose -f $REMOTE_DIR/docker-compose.yml logs -f'"
