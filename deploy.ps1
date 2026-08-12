# 速签服务器部署脚本
# 使用方法：在 PowerShell 中运行 .\deploy.ps1

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  速签服务器部署脚本" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$SERVER_IP = "39.96.76.211"
$SERVER_USER = "root"
$REMOTE_DIR = "/opt/jisign"
$LOCAL_DIR = "C:\Users\13266\Desktop\速签"

# 检查本地文件
Write-Host "[1/4] 检查本地文件..." -ForegroundColor Yellow
$files = @(
    "$LOCAL_DIR\server\.env",
    "$LOCAL_DIR\server\certs\alipay\app_private_key.pem",
    "$LOCAL_DIR\server\certs\alipay\appCertPublicKey_2021006170647946.crt",
    "$LOCAL_DIR\server\certs\alipay\alipayCertPublicKey_RSA2.crt",
    "$LOCAL_DIR\server\certs\alipay\alipayRootCert.crt"
)

$allExist = $true
foreach ($file in $files) {
    if (Test-Path $file) {
        Write-Host "  ✅ $(Split-Path $file -Leaf)" -ForegroundColor Green
    } else {
        Write-Host "  ❌ $(Split-Path $file -Leaf) - 文件不存在!" -ForegroundColor Red
        $allExist = $false
    }
}

if (-not $allExist) {
    Write-Host ""
    Write-Host "❌ 部分文件缺失，请先完成配置" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[2/4] 上传证书文件到服务器..." -ForegroundColor Yellow
Write-Host "  请输入服务器密码: $SERVER_USER@$SERVER_IP" -ForegroundColor Gray

# 上传证书目录
scp -r "$LOCAL_DIR\server\certs\alipay" "${SERVER_USER}@${SERVER_IP}:/opt/jisign/server/certs/"
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ❌ 证书上传失败" -ForegroundColor Red
    exit 1
}
Write-Host "  ✅ 证书文件上传成功" -ForegroundColor Green

Write-Host ""
Write-Host "[3/4] 上传 .env 配置文件..." -ForegroundColor Yellow
scp "$LOCAL_DIR\server\.env" "${SERVER_USER}@${SERVER_IP}:/opt/jisign/server/"
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ❌ .env 上传失败" -ForegroundColor Red
    exit 1
}
Write-Host "  ✅ .env 上传成功" -ForegroundColor Green

Write-Host ""
Write-Host "[4/4] 重启服务器..." -ForegroundColor Yellow
ssh "${SERVER_USER}@${SERVER_IP}" "cd /opt/jisign && docker compose restart server"
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ❌ 重启失败" -ForegroundColor Red
    exit 1
}
Write-Host "  ✅ 服务器重启成功" -ForegroundColor Green

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  部署完成！" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "验证步骤:" -ForegroundColor Yellow
Write-Host "1. 检查服务状态: ssh $SERVER_USER@$SERVER_IP 'docker compose -f /opt/jisign/docker-compose.yml ps'" -ForegroundColor Gray
Write-Host "2. 查看日志: ssh $SERVER_USER@$SERVER_IP 'docker compose -f /opt/jisign/docker-compose.yml logs server | tail 20'" -ForegroundColor Gray
Write-Host "3. 健康检查: curl https://api.susuq.top/health" -ForegroundColor Gray
Write-Host ""
