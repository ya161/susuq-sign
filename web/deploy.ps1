# 速签前端部署脚本（Windows PowerShell）
# 用法：在 PowerShell 中运行 .\deploy.ps1

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  速签前端性能优化部署脚本" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 服务器配置
$SERVER_IP = "39.96.76.211"
$SERVER_USER = "root"
$WEBSITE_PATH = "/opt/jisign/website"

Write-Host "[1/4] 清理本地缓存..." -ForegroundColor Yellow
if (Test-Path ".next") { Remove-Item -Recurse -Force ".next" }
if (Test-Path "out") { Remove-Item -Recurse -Force "out" }
if (Test-Path "node_modules\.cache") { Remove-Item -Recurse -Force "node_modules\.cache" }
Write-Host "      ✓ 缓存已清理" -ForegroundColor Green

Write-Host "[2/4] 编译生产版本..." -ForegroundColor Yellow
npm run build
if ($LASTEXITCODE -ne 0) {
    Write-Host "      ✗ 编译失败！" -ForegroundColor Red
    exit 1
}
Write-Host "      ✓ 编译成功" -ForegroundColor Green

Write-Host "[3/4] 上传到服务器..." -ForegroundColor Yellow
Write-Host "      正在删除服务器旧文件..."
ssh "$SERVER_USER@$SERVER_IP" "rm -rf $WEBSITE_PATH/_next $WEBSITE_PATH/install $WEBSITE_PATH/purchase"
Write-Host "      正在上传新文件..."
scp -r out/* "$SERVER_USER@$SERVER_IP`:$WEBSITE_PATH/"
if ($LASTEXITCODE -ne 0) {
    Write-Host "      ✗ 上传失败！" -ForegroundColor Red
    exit 1
}
Write-Host "      ✓ 上传完成" -ForegroundColor Green

Write-Host "[4/4] 设置权限..." -ForegroundColor Yellow
ssh "$SERVER_USER@$SERVER_IP" "chown -R www-data:www-data $WEBSITE_PATH/; chmod -R 755 $WEBSITE_PATH/"
Write-Host "      ✓ 权限设置完成" -ForegroundColor Green

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ✓ 部署完成！" -ForegroundColor Green
Write-Host "  访问 https://susuq.top 验证效果" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "提示：" -ForegroundColor Yellow
Write-Host "  1. 手机浏览器访问测试加载速度"
Write-Host "  2. 打开 Chrome DevTools > Network 查看加载时间"
Write-Host "  3. 如需配置 Nginx 缓存头，请参考 nginx-performance.conf"
