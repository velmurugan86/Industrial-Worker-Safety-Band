# ==============================================================================
# Industrial Worker Safety Band - Quick Services & Firewall Setup (Windows)
# Run in Administrator PowerShell
# ==============================================================================

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  Industrial Worker Safety Band - Environment Setup Helper" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Open Firewall Port 1883 for Mosquitto MQTT
Write-Host "`n[1/3] Configuring Windows Firewall for MQTT (Port 1883)..." -ForegroundColor Yellow
try {
    $existing = Get-NetFirewallRule -DisplayName "Mosquitto MQTT Port 1883" -ErrorAction SilentlyContinue
    if (-not $existing) {
        New-NetFirewallRule -DisplayName "Mosquitto MQTT Port 1883" `
                            -Direction Inbound `
                            -LocalPort 1883 `
                            -Protocol TCP `
                            -Action Allow | Out-Null
        Write-Host " -> Inbound firewall rule created successfully." -ForegroundColor Green
    } else {
        Write-Host " -> Firewall rule already exists." -ForegroundColor Green
    }
} catch {
    Write-Host " -> Note: Run this script as Administrator to auto-add firewall rules." -ForegroundColor Red
}

# 2. Display Local IP addresses
Write-Host "`n[2/3] Local Network IP Addresses (Find your Wi-Fi IPv4):" -ForegroundColor Yellow
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch "Loopback|vEthernet" } | ForEach-Object {
    Write-Host ("  [{0}] {1}" -f $_.InterfaceAlias, $_.IPAddress) -ForegroundColor Cyan
}
Write-Host " -> Put your Wi-Fi IPv4 address into arduino/IndustrialWorkerSafetyBand.ino (MQTT_SERVER)" -ForegroundColor White

# 3. Mosquitto Service Check
Write-Host "`n[3/3] Checking Mosquitto MQTT Service..." -ForegroundColor Yellow
$mosq = Get-Service -Name "mosquitto" -ErrorAction SilentlyContinue
if ($mosq) {
    Write-Host (" -> Mosquitto service found: Status = {0}" -f $mosq.Status) -ForegroundColor Green
    if ($mosq.Status -ne "Running") {
        Write-Host " -> Starting Mosquitto service..." -ForegroundColor Yellow
        Start-Service mosquitto
    }
} else {
    Write-Host " -> Mosquitto service not detected as an auto-service." -ForegroundColor Yellow
    Write-Host "    You can launch Mosquitto manually via: mosquitto -v" -ForegroundColor White
}

Write-Host "`nSetup helper check completed!`n" -ForegroundColor Green
