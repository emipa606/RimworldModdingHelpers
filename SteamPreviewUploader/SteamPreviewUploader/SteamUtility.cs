using System;
using System.Text.RegularExpressions;
using System.Threading;
using Steamworks;

namespace RimworldModReleaseTool
{
    public static class SteamUtility
    {
        private const int RIMWORLD_APP_INT = 294100;
        private static CallResult<SubmitItemUpdateResult_t> submitResultCallback;
        private static readonly AppId_t RIMWORLD = new AppId_t(RIMWORLD_APP_INT);
        private static readonly AutoResetEvent ready = new AutoResetEvent(false);
        private static bool _initialized;
        private static SubmitItemUpdateResult_t submitResult;

        public static void Init()
        {
            Environment.SetEnvironmentVariable("SteamAppId", RIMWORLD_APP_INT.ToString());
            try
            {
                _initialized = SteamAPI.Init();
                if (!_initialized)
                {
                    Console.WriteLine("Steam API failed to initialize.");
                }
                else
                {
                    SteamClient.SetWarningMessageHook((severity, text) => Console.WriteLine(text.ToString()));
                }
            }
            catch (Exception e)
            {
                Console.WriteLine("Error: ");
                Console.Write(e.Message);
            }
        }

        public static bool Upload(Mod mod)
        {
            // set up steam API call
            var handle = SteamUGC.StartItemUpdate(RIMWORLD, mod.PublishedFileId);

            SteamUGC.UpdateItemPreviewFile(handle, mod.PreviewIndex, mod.Preview);

            // start async call
            var call = SteamUGC.SubmitItemUpdate(handle, null);
            submitResultCallback = CallResult<SubmitItemUpdateResult_t>.Create(OnItemSubmitted);
            submitResultCallback.Set(call);

            // keep checking for async call to complete
            var lastStatus = "";
            while (!ready.WaitOne(500))
            {
                var status = SteamUGC.GetItemUpdateProgress(handle, out _, out _);
                SteamAPI.RunCallbacks();
                if (lastStatus == status.ToString() || status.ToString() == "k_EItemUpdateStatusInvalid")
                {
                    continue;
                }

                var niceStatus = status.ToString().Replace("k_EItemUpdateStatus", "");
                niceStatus = Regex.Replace(niceStatus, "(\\B[A-Z])", " $1");
                switch (niceStatus)
                {
                    case "Uploading Preview File":
                        Console.WriteLine($"{niceStatus} ({Math.Round((double)mod.PreviewBytes / 1000)} KB)");
                        break;
                    default:
                        Console.WriteLine(niceStatus);
                        break;
                }

                lastStatus = status.ToString();
            }

            // we have completed!
            if (submitResult.m_eResult != EResult.k_EResultOK)
            {
                Console.WriteLine($"Unexpected result: {submitResult.m_eResult}");
            }

            return true;
        }

        private static void OnItemSubmitted(SubmitItemUpdateResult_t result, bool failure)
        {
            Console.WriteLine($"submit callback called:{result.m_eResult} :: {result.m_nPublishedFileId}");

            // store result and let the main thread continue
            submitResult = result;
            ready.Set();
        }

        public static void Shutdown()
        {
            SteamAPI.Shutdown();
            _initialized = false;
        }
    }
}