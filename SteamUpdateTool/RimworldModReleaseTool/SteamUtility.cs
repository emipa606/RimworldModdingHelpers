﻿using System;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading;
using Steamworks;

namespace RimworldModReleaseTool
{
    public static class SteamUtility
    {
        private const int RIMWORLD_APP_INT = 294100;
        private static readonly AppId_t RIMWORLD = new AppId_t(RIMWORLD_APP_INT);
        private static readonly AutoResetEvent ready = new AutoResetEvent(false);
        private static CallResult<SubmitItemUpdateResult_t> submitResultCallback;
        private static CallResult<CreateItemResult_t> createResultCallback;
        private static CallResult<AddUGCDependencyResult_t> OnAddUGCDependencyCompletedCallResult;
        private static CallResult<AddAppDependencyResult_t> OnAddAppDependencyCompletedCallResult;
        private static CallResult<RemoveUGCDependencyResult_t> OnRemoveUGCDependencyCompletedCallResult;
        private static RemoveUGCDependencyResult_t removeUGCDependencyResult;
        private static AddUGCDependencyResult_t addUGCDependencyResult;
        private static AddAppDependencyResult_t addAppUGCDependencyResult;
        private static bool _initialized;

        private static SubmitItemUpdateResult_t submitResult;

        private static CreateItemResult_t createResult;

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

        public static bool Upload(Mod mod, string changeNotes)
        {
            if (string.IsNullOrEmpty(changeNotes))
            {
                changeNotes = $"[Auto-generated text]: Update on {DateTime.Now:yyyy-MM-dd HH:mm:ss}";
            }

            var creating = false;
            if (mod.PublishedFileId == PublishedFileId_t.Invalid)
            {
                // create item first.
                creating = true;
                if (!mod.SkipConfirm)
                {
                    Console.WriteLine("No PublishedFileId found, create new mod?");
                    Console.ReadLine();
                }

                if (!Create(mod))
                {
                    throw new Exception("mod creation failed!");
                }
            }

            // set up steam API call
            var handle = SteamUGC.StartItemUpdate(RIMWORLD, mod.PublishedFileId);
            SetItemAttributes(handle, mod, creating);

            // start async call
            var call = SteamUGC.SubmitItemUpdate(handle, changeNotes);
            submitResultCallback = CallResult<SubmitItemUpdateResult_t>.Create(OnItemSubmitted);
            OnAddUGCDependencyCompletedCallResult =
                CallResult<AddUGCDependencyResult_t>.Create(OnAddUGCDependencyCompleted);
            OnAddAppDependencyCompletedCallResult =
                CallResult<AddAppDependencyResult_t>.Create(OnAddAppDependencyCompleted);
            OnRemoveUGCDependencyCompletedCallResult =
                CallResult<RemoveUGCDependencyResult_t>.Create(OnRemoveUGCDependencyCompleted);
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
                    case "Uploading Content":
                        Console.WriteLine($"{niceStatus} ({Math.Round((double)mod.ModBytes / 1000)} KB)");
                        break;
                    case "Uploading Preview File":
                        Console.WriteLine($"{niceStatus} ({Math.Round((double)mod.PreviewBytes / 1000)} KB)");
                        if (mod.PreviewsBytes.Any())
                        {
                            Console.WriteLine(
                                $"and {mod.Previews.Count} preview-images ({Math.Round((double)mod.PreviewsBytes.Sum() / 1000)} KB)");
                        }

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

            if (creating)
            {
                SteamAPICall_t addDependencyHandle;
                foreach (var modDependency in mod.Dependencies)
                {
                    Console.WriteLine($"Setting dependency to mod with id {modDependency}");
                    addUGCDependencyResult = new AddUGCDependencyResult_t();
                    addDependencyHandle =
                        SteamUGC.AddDependency(mod.PublishedFileId, new PublishedFileId_t(modDependency));
                    OnAddUGCDependencyCompletedCallResult.Set(addDependencyHandle);
                    while (addUGCDependencyResult.m_eResult == EResult.k_EResultNone)
                    {
                        Thread.Sleep(5);
                        SteamAPI.RunCallbacks();
                    }
                }

                foreach (var modAppDependency in mod.AppDependencies)
                {
                    Console.WriteLine($"Setting app-dependency to mod with id {modAppDependency}");
                    addAppUGCDependencyResult = new AddAppDependencyResult_t();
                    var addAppDependencyHandle =
                        SteamUGC.AddAppDependency(mod.PublishedFileId, new AppId_t(modAppDependency));
                    OnAddAppDependencyCompletedCallResult.Set(addAppDependencyHandle);
                    while (addAppUGCDependencyResult.m_eResult == EResult.k_EResultNone)
                    {
                        Thread.Sleep(5);
                        SteamAPI.RunCallbacks();
                    }
                }

                addUGCDependencyResult = new AddUGCDependencyResult_t();
                if (mod.Name.Contains("(Continued)"))
                {
                    Console.WriteLine("Adding mod to ressurection-collection");
                    addDependencyHandle =
                        SteamUGC.AddDependency(new PublishedFileId_t(1541984105), mod.PublishedFileId);
                }
                else
                {
                    Console.WriteLine("Adding mod to personal-collection");
                    addDependencyHandle =
                        SteamUGC.AddDependency(new PublishedFileId_t(2228969861), mod.PublishedFileId);
                }

                OnAddUGCDependencyCompletedCallResult.Set(addDependencyHandle);
                while (addUGCDependencyResult.m_eResult == EResult.k_EResultNone)
                {
                    Thread.Sleep(5);
                    SteamAPI.RunCallbacks();
                }
            }

            if (!mod.Archived)
            {
                return submitResult.m_eResult == EResult.k_EResultOK;
            }

            removeUGCDependencyResult = new RemoveUGCDependencyResult_t();
            SteamAPICall_t removeDependencyHandle;
            if (mod.Name.Contains("(Continued)"))
            {
                Console.WriteLine("Removing mod from ressurection-collection");
                removeDependencyHandle =
                    SteamUGC.RemoveDependency(new PublishedFileId_t(1541984105), mod.PublishedFileId);
            }
            else
            {
                Console.WriteLine("Removing mod from personal-collection");
                removeDependencyHandle =
                    SteamUGC.RemoveDependency(new PublishedFileId_t(2228969861), mod.PublishedFileId);
            }

            OnRemoveUGCDependencyCompletedCallResult.Set(removeDependencyHandle);
            while (removeUGCDependencyResult.m_eResult == EResult.k_EResultNone)
            {
                Thread.Sleep(5);
                SteamAPI.RunCallbacks();
            }

            return submitResult.m_eResult == EResult.k_EResultOK;
        }

        private static void OnItemSubmitted(SubmitItemUpdateResult_t result, bool failure)
        {
            Console.WriteLine($"submit callback called:{result.m_eResult} :: {result.m_nPublishedFileId}");

            // store result and let the main thread continue
            submitResult = result;
            ready.Set();
        }

        public static bool Create(Mod mod)
        {
            // start async call
            var call = SteamUGC.CreateItem(RIMWORLD, 0);
            createResultCallback = CallResult<CreateItemResult_t>.Create(OnItemCreated);
            createResultCallback.Set(call);

            // keep checking for async call to complete
            while (!ready.WaitOne(500))
            {
                SteamAPI.RunCallbacks();
                Console.WriteLine("Waiting for item creation to complete.");
            }

            // we have completed!
            if (createResult.m_eResult != EResult.k_EResultOK)
            {
                Console.WriteLine(createResult.m_eResult);
            }
            else
            {
                mod.PublishedFileId = createResult.m_nPublishedFileId;
                Console.WriteLine($"New mod created ({mod.PublishedFileId})");
                var path = $@"{mod.ContentFolder}\About\PublishedFileId.txt";
                if (File.Exists(path))
                {
                    return createResult.m_eResult == EResult.k_EResultOK;
                }

                // Create a file to write to.
                using (var sw = File.CreateText(path))
                {
                    sw.Write(mod.PublishedFileId);
                }
            }

            return createResult.m_eResult == EResult.k_EResultOK;
        }

        private static void OnItemCreated(CreateItemResult_t result, bool failure)
        {
            // store result and let the main thread continue
            createResult = result;
            ready.Set();
        }

        private static void SetItemAttributes(UGCUpdateHandle_t handle, Mod mod, bool creating)
        {
            SteamUGC.SetItemTitle(handle, mod.Name);
            SteamUGC.SetItemTags(handle, mod.Tags);
            SteamUGC.SetItemContent(handle, mod.ContentFolder);
            if (mod.Preview != null)
            {
                SteamUGC.SetItemPreview(handle, mod.Preview);
            }

            if (creating)
            {
                SteamUGC.SetItemDescription(handle, mod.Description);
                SteamUGC.SetItemVisibility(handle,
                    ERemoteStoragePublishedFileVisibility.k_ERemoteStoragePublishedFileVisibilityPublic);
                foreach (var modPreview in mod.Previews)
                {
                    SteamUGC.AddItemPreviewFile(handle, modPreview, EItemPreviewType.k_EItemPreviewType_Image);
                }

                Console.WriteLine($"Adding {mod.Previews.Count} preview images");
            }

            if (mod.Archived)
            {
                SteamUGC.SetItemVisibility(handle,
                    ERemoteStoragePublishedFileVisibility.k_ERemoteStoragePublishedFileVisibilityUnlisted);
            }
        }

        private static void OnRemoveUGCDependencyCompleted(RemoveUGCDependencyResult_t pCallback, bool bIOFailure)
        {
            removeUGCDependencyResult = pCallback;
        }

        private static void OnAddUGCDependencyCompleted(AddUGCDependencyResult_t pCallback, bool bIOFailure)
        {
            addUGCDependencyResult = pCallback;
        }

        private static void OnAddAppDependencyCompleted(AddAppDependencyResult_t pCallback, bool bIOFailure)
        {
            addAppUGCDependencyResult = pCallback;
        }

        public static void Shutdown()
        {
            SteamAPI.Shutdown();
            _initialized = false;
        }
    }
}