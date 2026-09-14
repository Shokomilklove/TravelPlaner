# ============================================================
# TravelPlanner - Windows WireGuard Bootstrap
# ============================================================

$ErrorActionPreference = "Stop"

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

$AwsRegion = "eu-central-1"

$AwsInstanceName = "travel-planner-k3s"

$SsmAwsPublicKeyName = "/travel-planner/wireguard/aws-public-key"
$SsmWindowsPublicKeyName = "/travel-planner/wireguard/windows-public-key"

$WindowsWgAddress = "10.50.0.1/24"
$AwsWgAddress = "10.50.0.2"

# K3s default Flannel Pod CIDR
$KubernetesPodCIDR = "10.42.0.0/16"

$WgConfigDirectory = "C:\Program Files\WireGuard"
$WgConfigPath = "$WgConfigDirectory\travel-planner.conf"

$PrivateKeyPath = "$WgConfigDirectory\windows-private.key"
$PublicKeyPath = "$WgConfigDirectory\windows-public.key"

# ------------------------------------------------------------
# Require Administrator
# ------------------------------------------------------------

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)

if (-not $currentPrincipal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {

    Write-Host ""
    Write-Host "ERROR: PowerShell must be started as Administrator." -ForegroundColor Red
    Write-Host ""

    exit 1
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " TravelPlanner WireGuard Bootstrap" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# ------------------------------------------------------------
# Check AWS CLI
# ------------------------------------------------------------

Write-Host "[1/8] Checking AWS CLI..." -ForegroundColor Yellow

if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {

    Write-Host ""
    Write-Host "ERROR: AWS CLI is not installed." -ForegroundColor Red
    Write-Host "Install AWS CLI and configure credentials first." -ForegroundColor Red
    Write-Host ""

    exit 1
}

aws --version

# ------------------------------------------------------------
# Check AWS credentials
# ------------------------------------------------------------

Write-Host ""
Write-Host "[2/8] Checking AWS credentials..." -ForegroundColor Yellow

try {

    $identity = aws sts get-caller-identity `
        --region $AwsRegion `
        --output json |
        ConvertFrom-Json

}
catch {

    Write-Host ""
    Write-Host "ERROR: AWS credentials are not configured." -ForegroundColor Red
    Write-Host ""
    Write-Host "Run:" -ForegroundColor Yellow
    Write-Host "aws configure" -ForegroundColor White
    Write-Host ""

    exit 1
}

Write-Host "AWS account: $($identity.Account)" -ForegroundColor Green

# ------------------------------------------------------------
# Get AWS EC2 public IP
# ------------------------------------------------------------

Write-Host ""
Write-Host "[3/8] Getting AWS k3s public IP..." -ForegroundColor Yellow

$AwsPublicIp = aws ec2 describe-instances `
    --region $AwsRegion `
    --filters `
        "Name=tag:Name,Values=$AwsInstanceName" `
        "Name=instance-state-name,Values=running" `
    --query "Reservations[0].Instances[0].PublicIpAddress" `
    --output text

if (
    [string]::IsNullOrWhiteSpace($AwsPublicIp) -or
    $AwsPublicIp -eq "None"
) {

    Write-Host ""
    Write-Host "ERROR: Could not find running EC2 instance '$AwsInstanceName'." -ForegroundColor Red
    Write-Host ""

    exit 1
}

Write-Host "AWS public IP: $AwsPublicIp" -ForegroundColor Green

# ------------------------------------------------------------
# Get AWS WireGuard public key
# ------------------------------------------------------------

Write-Host ""
Write-Host "[4/8] Getting AWS WireGuard public key..." -ForegroundColor Yellow

$AwsPublicKey = aws ssm get-parameter `
    --region $AwsRegion `
    --name $SsmAwsPublicKeyName `
    --query "Parameter.Value" `
    --output text

if (
    [string]::IsNullOrWhiteSpace($AwsPublicKey) -or
    $AwsPublicKey -eq "None"
) {

    Write-Host ""
    Write-Host "ERROR: AWS WireGuard public key is not available in SSM." -ForegroundColor Red
    Write-Host ""
    Write-Host "AWS bootstrap must publish:" -ForegroundColor Yellow
    Write-Host $SsmAwsPublicKeyName -ForegroundColor White
    Write-Host ""

    exit 1
}

Write-Host "AWS WireGuard public key received." -ForegroundColor Green

# ------------------------------------------------------------
# Check WireGuard
# ------------------------------------------------------------

Write-Host ""
Write-Host "[5/8] Checking WireGuard..." -ForegroundColor Yellow

$WireGuardExe = "C:\Program Files\WireGuard\wireguard.exe"
$WgExe = "C:\Program Files\WireGuard\wg.exe"

if (-not (Test-Path $WireGuardExe)) {

    Write-Host ""
    Write-Host "ERROR: WireGuard is not installed." -ForegroundColor Red
    Write-Host ""
    Write-Host "Install WireGuard for Windows first." -ForegroundColor Yellow
    Write-Host ""

    exit 1
}

if (-not (Test-Path $WgExe)) {

    Write-Host ""
    Write-Host "ERROR: wg.exe was not found." -ForegroundColor Red
    Write-Host ""

    exit 1
}

Write-Host "WireGuard found." -ForegroundColor Green

# ------------------------------------------------------------
# Create WireGuard directory
# ------------------------------------------------------------

if (-not (Test-Path $WgConfigDirectory)) {

    New-Item `
        -ItemType Directory `
        -Path $WgConfigDirectory `
        -Force |
        Out-Null
}

# ------------------------------------------------------------
# Generate Windows WireGuard keypair
# ------------------------------------------------------------

Write-Host ""
Write-Host "[6/8] Generating Windows WireGuard key..." -ForegroundColor Yellow

if (-not (Test-Path $PrivateKeyPath)) {

    Write-Host "Generating new private key..."

    $WindowsPrivateKey = & $WgExe genkey

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to generate WireGuard private key."
    }

    $WindowsPrivateKey |
        Out-File `
            -FilePath $PrivateKeyPath `
            -Encoding ascii `
            -NoNewline

}
else {

    Write-Host "Existing Windows private key found."

    $WindowsPrivateKey = Get-Content $PrivateKeyPath -Raw
    $WindowsPrivateKey = $WindowsPrivateKey.Trim()
}

if ([string]::IsNullOrWhiteSpace($WindowsPrivateKey)) {

    throw "Windows private key is empty."
}

# ------------------------------------------------------------
# Generate public key
# ------------------------------------------------------------

$WindowsPublicKey = $WindowsPrivateKey |
    & $WgExe pubkey

if ($LASTEXITCODE -ne 0) {
    throw "Failed to generate WireGuard public key."
}

$WindowsPublicKey = $WindowsPublicKey.Trim()

$WindowsPublicKey |
    Out-File `
        -FilePath $PublicKeyPath `
        -Encoding ascii `
        -NoNewline

Write-Host "Windows public key generated." -ForegroundColor Green

# ------------------------------------------------------------
# Upload Windows public key to AWS SSM
# ------------------------------------------------------------

Write-Host ""
Write-Host "[7/8] Sending Windows public key to AWS SSM..." -ForegroundColor Yellow

aws ssm put-parameter `
    --region $AwsRegion `
    --name $SsmWindowsPublicKeyName `
    --type String `
    --value $WindowsPublicKey `
    --overwrite `
    --output text

if ($LASTEXITCODE -ne 0) {

    Write-Host ""
    Write-Host "ERROR: Failed to upload Windows public key." -ForegroundColor Red
    Write-Host ""

    exit 1
}

Write-Host "Windows public key uploaded to AWS." -ForegroundColor Green

# ------------------------------------------------------------
# Create WireGuard configuration
# ------------------------------------------------------------

Write-Host ""
Write-Host "Creating WireGuard configuration..." -ForegroundColor Yellow

$Config = @"
[Interface]
Address = $WindowsWgAddress
PrivateKey = $WindowsPrivateKey

[Peer]
PublicKey = $AwsPublicKey
Endpoint = ${AwsPublicIp}:51820
AllowedIPs = $AwsWgAddress/32, $KubernetesPodCIDR
PersistentKeepalive = 25
"@

$Config |
    Out-File `
        -FilePath $WgConfigPath `
        -Encoding ascii `
        -Force

Write-Host "Configuration created:" -ForegroundColor Green
Write-Host $WgConfigPath -ForegroundColor Gray

# ------------------------------------------------------------
# Remove old tunnel if running
# ------------------------------------------------------------

Write-Host ""
Write-Host "[8/8] Starting WireGuard..." -ForegroundColor Yellow

$TunnelName = "travel-planner"

& $WireGuardExe /uninstalltunnelservice $TunnelName 2>$null

Start-Sleep -Seconds 2

# ------------------------------------------------------------
# Install / start tunnel
# ------------------------------------------------------------

& $WireGuardExe /installtunnelservice $WgConfigPath

if ($LASTEXITCODE -ne 0) {

    Write-Host ""
    Write-Host "ERROR: WireGuard tunnel failed to start." -ForegroundColor Red
    Write-Host ""

    exit 1
}

Start-Sleep -Seconds 3

# ------------------------------------------------------------
# Verify
# ------------------------------------------------------------

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " WireGuard status" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

& $WgExe show

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host " TravelPlanner WireGuard started" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""

Write-Host "Windows WG IP : 10.50.0.1" -ForegroundColor White
Write-Host "AWS WG IP     : 10.50.0.2" -ForegroundColor White
Write-Host "AWS public IP : $AwsPublicIp" -ForegroundColor White
Write-Host "AI Planner    : 10.50.0.1:5002" -ForegroundColor White
Write-Host ""