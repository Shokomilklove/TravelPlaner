#Requires -Version 5.1

$ErrorActionPreference = "Stop"

# ==============================
# TravelPlanner WireGuard setup
# ==============================

$Region       = "eu-central-1"
$AwsPublicIp  = "51.102.241.137"
$TunnelName   = "TravelPlanner"

$WindowsIp    = "10.50.0.1"
$AwsVpnIp     = "10.50.0.2"

$SsmWindowsPublicKey = "/travel-planner/wireguard/windows-public-key"
$SsmAwsPublicKey     = "/travel-planner/wireguard/aws-public-key"

$WireGuardDir = "C:\ProgramData\TravelPlanner\WireGuard"
$PrivateKeyFile = Join-Path $WireGuardDir "windows-private.key"
$PublicKeyFile  = Join-Path $WireGuardDir "windows-public.key"
$ConfigFile     = Join-Path $WireGuardDir "$TunnelName.conf"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " TravelPlanner WireGuard setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# --------------------------------
# Check Administrator
# --------------------------------

$principal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)

if (-not $principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    Write-Host "ERROR: Run PowerShell as Administrator." -ForegroundColor Red
    exit 1
}

# --------------------------------
# Check AWS CLI
# --------------------------------

if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: AWS CLI is not installed." -ForegroundColor Red
    Write-Host "Install AWS CLI first, then run this script again."
    exit 1
}

Write-Host "[OK] AWS CLI found" -ForegroundColor Green

# --------------------------------
# Check AWS credentials
# --------------------------------

Write-Host "Checking AWS credentials..."

try {
    $identity = aws sts get-caller-identity `
        --region $Region `
        --output json 2>$null | ConvertFrom-Json

    if (-not $identity) {
        throw "AWS identity check failed"
    }

    Write-Host "[OK] AWS authentication works" -ForegroundColor Green
}
catch {
    Write-Host "ERROR: AWS authentication failed." -ForegroundColor Red
    Write-Host "Run 'aws configure' or use your existing AWS credentials."
    exit 1
}

# --------------------------------
# Find WireGuard
# --------------------------------

$WgExe = $null
$WireGuardExe = $null

$PossibleWg = @(
    "C:\Program Files\WireGuard\wg.exe",
    "C:\Program Files (x86)\WireGuard\wg.exe"
)

$PossibleWireGuard = @(
    "C:\Program Files\WireGuard\wireguard.exe",
    "C:\Program Files (x86)\WireGuard\wireguard.exe"
)

foreach ($path in $PossibleWg) {
    if (Test-Path $path) {
        $WgExe = $path
        break
    }
}

foreach ($path in $PossibleWireGuard) {
    if (Test-Path $path) {
        $WireGuardExe = $path
        break
    }
}

# --------------------------------
# Install WireGuard if necessary
# --------------------------------

if (-not $WgExe -or -not $WireGuardExe) {

    Write-Host "WireGuard not found." -ForegroundColor Yellow
    Write-Host "Trying to install WireGuard with winget..."

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host "ERROR: winget is not available." -ForegroundColor Red
        Write-Host "Install WireGuard manually from the official WireGuard application."
        exit 1
    }

    winget install `
        --id WireGuard.WireGuard `
        --exact `
        --accept-package-agreements `
        --accept-source-agreements

    Start-Sleep -Seconds 3

    foreach ($path in $PossibleWg) {
        if (Test-Path $path) {
            $WgExe = $path
            break
        }
    }

    foreach ($path in $PossibleWireGuard) {
        if (Test-Path $path) {
            $WireGuardExe = $path
            break
        }
    }
}

if (-not $WgExe -or -not $WireGuardExe) {
    Write-Host "ERROR: WireGuard executable was not found." -ForegroundColor Red
    exit 1
}

Write-Host "[OK] WireGuard found" -ForegroundColor Green

# --------------------------------
# Create directory
# --------------------------------

New-Item `
    -ItemType Directory `
    -Force `
    -Path $WireGuardDir | Out-Null

# --------------------------------
# Generate Windows keypair
# --------------------------------

if (-not (Test-Path $PrivateKeyFile)) {

    Write-Host ""
    Write-Host "Generating Windows WireGuard keypair..."

    $privateKey = & $WgExe genkey

    if (-not $privateKey) {
        throw "Failed to generate WireGuard private key."
    }

    $privateKey.Trim() | Set-Content `
        -Path $PrivateKeyFile `
        -NoNewline `
        -Encoding ascii

    $privateKey = $privateKey.Trim()

    $publicKey = $privateKey | & $WgExe pubkey

    $publicKey.Trim() | Set-Content `
        -Path $PublicKeyFile `
        -NoNewline `
        -Encoding ascii

    Write-Host "[OK] New WireGuard keypair generated" -ForegroundColor Green
}
else {

    Write-Host "[OK] Existing Windows private key found" -ForegroundColor Green

    $privateKey = (Get-Content $PrivateKeyFile -Raw).Trim()

    if (-not $privateKey) {
        throw "Windows private key is empty."
    }

    $publicKey = $privateKey | & $WgExe pubkey

    $publicKey.Trim() | Set-Content `
        -Path $PublicKeyFile `
        -NoNewline `
        -Encoding ascii
}

$publicKey = $publicKey.Trim()

Write-Host ""
Write-Host "Windows public key:" -ForegroundColor Cyan
Write-Host $publicKey
Write-Host ""

# --------------------------------
# Upload Windows public key to SSM
# --------------------------------

Write-Host "Uploading Windows public key to AWS SSM..."

aws ssm put-parameter `
    --region $Region `
    --name $SsmWindowsPublicKey `
    --type String `
    --value $publicKey `
    --overwrite `
    --output text | Out-Null

Write-Host "[OK] Windows public key uploaded to SSM" -ForegroundColor Green

# --------------------------------
# Get AWS public key from SSM
# --------------------------------

Write-Host "Getting AWS WireGuard public key from SSM..."

try {

    $AwsPublicKey = aws ssm get-parameter `
        --region $Region `
        --name $SsmAwsPublicKey `
        --query "Parameter.Value" `
        --output text 2>$null

    $AwsPublicKey = $AwsPublicKey.Trim()

}
catch {
    $AwsPublicKey = ""
}

if (
    -not $AwsPublicKey -or
    $AwsPublicKey -eq "None"
) {
    Write-Host ""
    Write-Host "ERROR: AWS public key was not found in SSM:" -ForegroundColor Red
    Write-Host $SsmAwsPublicKey
    Write-Host ""
    Write-Host "AWS must publish its WireGuard public key to SSM first."
    exit 1
}

Write-Host "[OK] AWS public key received from SSM" -ForegroundColor Green

# --------------------------------
# Create WireGuard config
# --------------------------------

Write-Host "Creating WireGuard configuration..."

$config = @"
[Interface]
PrivateKey = $privateKey
Address = $WindowsIp/24

[Peer]
PublicKey = $AwsPublicKey
Endpoint = ${AwsPublicIp}:51820
AllowedIPs = $AwsVpnIp/32
PersistentKeepalive = 25
"@

$config | Set-Content `
    -Path $ConfigFile `
    -Encoding ascii

# --------------------------------
# Secure private key/config files
# --------------------------------

Write-Host "Securing WireGuard files..."

icacls $WireGuardDir /inheritance:r | Out-Null
icacls $WireGuardDir /grant:r "$env:USERNAME:(OI)(CI)F" | Out-Null
icacls $WireGuardDir /grant:r "SYSTEM:(OI)(CI)F" | Out-Null
icacls $WireGuardDir /grant:r "Administrators:(OI)(CI)F" | Out-Null

# --------------------------------
# Remove old TravelPlanner tunnel
# --------------------------------

Write-Host ""
Write-Host "Removing old TravelPlanner tunnel if present..."

& $WireGuardExe /uninstalltunnelservice $TunnelName 2>$null

Start-Sleep -Seconds 2

# --------------------------------
# Install tunnel service
# --------------------------------

Write-Host "Installing TravelPlanner tunnel..."

& $WireGuardExe /installtunnelservice $ConfigFile

Start-Sleep -Seconds 5

# --------------------------------
# Check tunnel
# --------------------------------

Write-Host ""
Write-Host "Checking WireGuard interface..."

$wgShow = & $WgExe show $TunnelName 2>$null

if (-not $wgShow) {
    Write-Host "ERROR: WireGuard tunnel did not start." -ForegroundColor Red
    exit 1
}

Write-Host "[OK] WireGuard tunnel is running" -ForegroundColor Green

# --------------------------------
# Wait for handshake
# --------------------------------

Write-Host ""
Write-Host "Waiting for WireGuard handshake..."

$handshakeOk = $false

for ($i = 1; $i -le 12; $i++) {

    Start-Sleep -Seconds 2

    $wgShow = & $WgExe show $TunnelName 2>$null

    if ($wgShow -match "latest handshake") {
        $handshakeOk = $true
        break
    }

    Write-Host "  waiting... ($i/12)"
}

if ($handshakeOk) {
    Write-Host "[OK] WireGuard handshake detected" -ForegroundColor Green
}
else {
    Write-Host ""
    Write-Host "WARNING: WireGuard handshake was not detected." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Current WireGuard status:"
    & $WgExe show $TunnelName
    Write-Host ""
}

# --------------------------------
# Test AWS VPN IP
# --------------------------------

Write-Host ""
Write-Host "Testing AWS WireGuard endpoint $AwsVpnIp..."

$pingResult = Test-Connection `
    -ComputerName $AwsVpnIp `
    -Count 2 `
    -Quiet `
    -ErrorAction SilentlyContinue

if ($pingResult) {
    Write-Host "[OK] AWS VPN IP responds to ping" -ForegroundColor Green
}
else {
    Write-Host "[INFO] Ping is unavailable/blocked." -ForegroundColor Yellow
}

# --------------------------------
# Test AI Planner
# --------------------------------

Write-Host ""
Write-Host "Testing AI Planner on $WindowsIp`:5002..."

try {

    $response = Invoke-RestMethod `
        -Uri "http://${WindowsIp}:5002/health" `
        -TimeoutSec 5

    if ($response.status -eq "ok") {
        Write-Host "[OK] AI Planner is reachable through WireGuard" -ForegroundColor Green
        Write-Host "     $($response | ConvertTo-Json -Compress)"
    }
    else {
        Write-Host "[WARNING] AI Planner responded, but status is not OK." -ForegroundColor Yellow
    }

}
catch {

    Write-Host ""
    Write-Host "[WARNING] AI Planner is not reachable through WireGuard." -ForegroundColor Yellow
    Write-Host $_.Exception.Message
    Write-Host ""

    Write-Host "Check:"
    Write-Host "  Windows firewall TCP 5002"
    Write-Host "  AI Planner Docker container"
    Write-Host "  WireGuard handshake"
}

# --------------------------------
# Final status
# --------------------------------

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " TravelPlanner setup completed" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Windows VPN IP : $WindowsIp"
Write-Host "AWS VPN IP     : $AwsVpnIp"
Write-Host "AWS endpoint   : ${AwsPublicIp}:51820"
Write-Host ""

Write-Host "WireGuard status:"
& $WgExe show $TunnelName

Write-Host ""
Write-Host "AI Planner:"
Write-Host "http://${WindowsIp}:5002/health"

Write-Host ""