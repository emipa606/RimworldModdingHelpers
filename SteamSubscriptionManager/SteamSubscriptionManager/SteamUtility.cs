using System;
using System.Runtime.InteropServices;
using System.Threading;
using Steamworks;

namespace SteamCollectionManager
{
    public static class SteamUtility
    {
        private const int RIMWORLD_APP_INT = 294100;
        private const int STD_OUTPUT_HANDLE = -11;
        private const int STD_ERROR_HANDLE = -12;
        private const uint GENERIC_WRITE = 0x40000000;
        private const uint FILE_SHARE_READ = 1;
        private const uint FILE_SHARE_WRITE = 2;
        private const uint OPEN_EXISTING = 3;
        private const int DownloadPollIntervalMs = 100;
        private const int StatePollIntervalMs = 100;

        private static bool _initialized;

        private static RemoteStorageSubscribePublishedFileResult_t remoteStorageSubscribePublishedFileResult;

        private static CallResult<RemoteStorageSubscribePublishedFileResult_t>
            OnRemoteStorageSubscribePublishedFileResult;

        private static RemoteStorageUnsubscribePublishedFileResult_t remoteStorageUnsubscribePublishedFileResult;

        private static CallResult<RemoteStorageUnsubscribePublishedFileResult_t>
            OnRemoteStorageUnsubscribePublishedFileResult;

        public static void SetSubscription(string modId, bool subscribe, bool fast)
        {
            Console.ForegroundColor = ConsoleColor.DarkGray;
            if (!Init())
            {
                Console.ForegroundColor = ConsoleColor.DarkRed;
                Console.WriteLine("Failed to init");
                return;
            }

            var modFileId = new PublishedFileId_t(Convert.ToUInt64(modId));
            try
            {
                if (subscribe)
                {
                    OnRemoteStorageSubscribePublishedFileResult =
                        CallResult<RemoteStorageSubscribePublishedFileResult_t>.Create(
                            OnRemoteStorageSubscribePublishedFileCompleted);
                    remoteStorageSubscribePublishedFileResult = new RemoteStorageSubscribePublishedFileResult_t();
                    var subscribeHandle = SteamUGC.SubscribeItem(modFileId);
                    OnRemoteStorageSubscribePublishedFileResult.Set(subscribeHandle);

                    Console.Write(" ");
                    using (new Spinner())
                    {
                        while (remoteStorageSubscribePublishedFileResult.m_eResult == EResult.k_EResultNone)
                        {
                            Thread.Sleep(5);
                            SteamAPI.RunCallbacks();
                        }
                    }

                    Thread.Sleep(50);
                    SteamUGC.DownloadItem(modFileId, true);

                    if (!fast)
                    {
                        WaitForDownloadWithProgress(modFileId);
                    }
                }
                else
                {
                    OnRemoteStorageUnsubscribePublishedFileResult =
                        CallResult<RemoteStorageUnsubscribePublishedFileResult_t>.Create(
                            OnRemoteStorageUnsubscribePublishedFileCompleted);
                    remoteStorageUnsubscribePublishedFileResult = new RemoteStorageUnsubscribePublishedFileResult_t();
                    var unsubscribeHandle = SteamUGC.UnsubscribeItem(modFileId);
                    OnRemoteStorageUnsubscribePublishedFileResult.Set(unsubscribeHandle);

                    Console.Write(" ");
                    using (new Spinner())
                    {
                        while (remoteStorageUnsubscribePublishedFileResult.m_eResult == EResult.k_EResultNone)
                        {
                            Thread.Sleep(5);
                            SteamAPI.RunCallbacks();
                        }
                    }
                }
            }
            catch (Exception exception)
            {
                Console.ForegroundColor = ConsoleColor.DarkRed;
                Console.WriteLine("Error while managing subscription: ");
                Console.Write(exception.Message);
            }

            Shutdown();
        }

        private static void WaitForDownloadWithProgress(PublishedFileId_t modFileId)
        {
            var retryCount = 0;
            using (var progressBar = new ProgressBar())
            {
                while (true)
                {
                    SteamAPI.RunCallbacks();

                    ulong bytesDownloaded;
                    ulong bytesTotal;
                    if (SteamUGC.GetItemDownloadInfo(modFileId, out bytesDownloaded, out bytesTotal) && bytesTotal > 0)
                    {
                        progressBar.Report(bytesDownloaded / (double)bytesTotal);
                    }

                    var state = (uint)SteamUGC.GetItemState(modFileId);
                    var isInstalled = (state & (uint)EItemState.k_EItemStateInstalled) != 0;
                    var isDownloading = (state & (uint)EItemState.k_EItemStateDownloading) != 0;
                    var isDownloadPending = (state & (uint)EItemState.k_EItemStateDownloadPending) != 0;
                    var needsUpdate = (state & (uint)EItemState.k_EItemStateNeedsUpdate) != 0;

                    if (isInstalled && !needsUpdate && !isDownloading && !isDownloadPending)
                    {
                        progressBar.Report(1.0);
                        break;
                    }

                    if (!isDownloading && !isDownloadPending && !isInstalled && retryCount < 2)
                    {
                        SteamUGC.DownloadItem(modFileId, true);
                        retryCount++;
                    }

                    Thread.Sleep(DownloadPollIntervalMs);
                }
            }
        }

        private static bool Init()
        {
            Environment.SetEnvironmentVariable("SteamAppId", RIMWORLD_APP_INT.ToString());
            try
            {
                // Save original stdout/stderr handles
                var originalStdOut = GetStdHandle(STD_OUTPUT_HANDLE);
                var originalStdErr = GetStdHandle(STD_ERROR_HANDLE);

                // Redirect stdout and stderr to NUL device
                var nullHandle = CreateFileA("NUL", GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE,
                    IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);

                if (nullHandle != new IntPtr(-1))
                {
                    SetStdHandle(STD_OUTPUT_HANDLE, nullHandle);
                    SetStdHandle(STD_ERROR_HANDLE, nullHandle);
                }

                _initialized = SteamAPI.Init();

                // Restore original handles
                SetStdHandle(STD_OUTPUT_HANDLE, originalStdOut);
                SetStdHandle(STD_ERROR_HANDLE, originalStdErr);

                if (!_initialized)
                {
                    Console.ForegroundColor = ConsoleColor.DarkRed;
                    Console.WriteLine("Steam API failed to initialize.");
                }
            }
            catch (Exception exception)
            {
                Console.ForegroundColor = ConsoleColor.DarkRed;
                Console.WriteLine($"Error: {exception}");
                return false;
            }

            return true;
        }

        private static void Shutdown()
        {
            SteamAPI.Shutdown();
            _initialized = false;
        }

        private static void OnRemoteStorageSubscribePublishedFileCompleted(
            RemoteStorageSubscribePublishedFileResult_t pCallback, bool bIOFailure)
        {
            remoteStorageSubscribePublishedFileResult = pCallback;
        }

        private static void OnRemoteStorageUnsubscribePublishedFileCompleted(
            RemoteStorageUnsubscribePublishedFileResult_t pCallback, bool bIOFailure)
        {
            remoteStorageUnsubscribePublishedFileResult = pCallback;
        }

        private static void OnDownloadItemResultCompleted(DownloadItemResult_t pCallback)
        {
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr GetStdHandle(int nStdHandle);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool SetStdHandle(int nStdHandle, IntPtr hHandle);

        [DllImport("kernel32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
        private static extern IntPtr CreateFileA(
            string lpFileName,
            uint dwDesiredAccess,
            uint dwShareMode,
            IntPtr lpSecurityAttributes,
            uint dwCreationDisposition,
            uint dwFlagsAndAttributes,
            IntPtr hTemplateFile);
    }
}