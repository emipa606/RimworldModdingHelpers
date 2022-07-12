using System;
using System.Threading;
using Steamworks;

namespace SteamCollectionManager
{
    public static class SteamUtility
    {
        private const int RIMWORLD_APP_INT = 294100;
        private static bool _initialized;

        private static RemoteStorageSubscribePublishedFileResult_t remoteStorageSubscribePublishedFileResult;

        private static Callback<DownloadItemResult_t> OnDownloadItemResult;

        private static DownloadItemResult_t downloadItemResult;

        private static CallResult<RemoteStorageSubscribePublishedFileResult_t>
            OnRemoteStorageSubscribePublishedFileResult;

        private static RemoteStorageUnsubscribePublishedFileResult_t remoteStorageUnsubscribePublishedFileResult;

        private static CallResult<RemoteStorageUnsubscribePublishedFileResult_t>
            OnRemoteStorageUnsubscribePublishedFileResult;

        public static void SetSubscription(string modId, bool subscribe)
        {
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
                    OnDownloadItemResult = Callback<DownloadItemResult_t>.Create(OnDownloadItemResultCompleted);
                    remoteStorageSubscribePublishedFileResult = new RemoteStorageSubscribePublishedFileResult_t();
                    Console.WriteLine("Subscribing");
                    var subscribeHandle = SteamUGC.SubscribeItem(modFileId);
                    OnRemoteStorageSubscribePublishedFileResult.Set(subscribeHandle);
                    while (remoteStorageSubscribePublishedFileResult.m_eResult == EResult.k_EResultNone)
                    {
                        Thread.Sleep(5);
                        SteamAPI.RunCallbacks();
                    }

                    SteamUGC.DownloadItem(modFileId, true);
                    Console.WriteLine("Subscribed, initiating download");
                    while (downloadItemResult.m_eResult == EResult.k_EResultNone)
                    {
                        Thread.Sleep(5);
                        SteamAPI.RunCallbacks();
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
                    while (remoteStorageUnsubscribePublishedFileResult.m_eResult == EResult.k_EResultNone)
                    {
                        Thread.Sleep(5);
                        SteamAPI.RunCallbacks();
                    }
                }

                Console.ForegroundColor = ConsoleColor.DarkGreen;
                Console.WriteLine("Done!");
            }
            catch (Exception exception)
            {
                Console.ForegroundColor = ConsoleColor.DarkRed;
                Console.WriteLine("Error while managing subscription: ");
                Console.Write(exception.Message);
            }

            Shutdown();
        }

        private static bool Init()
        {
            Environment.SetEnvironmentVariable("SteamAppId", RIMWORLD_APP_INT.ToString());
            try
            {
                _initialized = SteamAPI.Init();
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
            downloadItemResult = pCallback;
        }
    }
}