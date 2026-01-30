using System;
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
        private static CallResult<SteamUGCQueryCompleted_t> OnSteamUGCQueryCompletedCallResult;
        private static CallResult<SteamUGCRequestUGCDetailsResult_t> OnSteamUGCRequestUGCDetailsResultCallResult;
        private static RemoveUGCDependencyResult_t removeUGCDependencyResult;
        private static SteamUGCRequestUGCDetailsResult_t dependencyResult;
        private static SteamUGCQueryCompleted_t collectionQueryResult;
        private static AddUGCDependencyResult_t addUGCDependencyResult;
        private static AddAppDependencyResult_t addAppUGCDependencyResult;
        private static bool _initialized;
        private static UGCQueryHandle_t m_UGCQueryHandle;

        private static SubmitItemUpdateResult_t submitResult;

        private static CreateItemResult_t createResult;

        public static void Init()
        {
            Console.ForegroundColor = ConsoleColor.Gray;
            Environment.SetEnvironmentVariable("SteamAppId", RIMWORLD_APP_INT.ToString());
            try
            {
                _initialized = SteamAPI.Init();
                if (!_initialized)
                {
                    Console.ForegroundColor = ConsoleColor.DarkRed;
                    Console.WriteLine("Steam API failed to initialize.");
                }
                else
                {
                    SteamClient.SetWarningMessageHook((severity, text) => Console.WriteLine(text.ToString()));
                }
            }
            catch (Exception e)
            {
                Console.ForegroundColor = ConsoleColor.DarkRed;
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
                    Console.ForegroundColor = ConsoleColor.White;
                    Console.WriteLine("No PublishedFileId found, create new mod?");
                    Console.ReadLine();
                }

                if (!create(mod))
                {
                    Console.ForegroundColor = ConsoleColor.DarkRed;
                    throw new Exception("mod creation failed!");
                }
            }

            Console.ForegroundColor = ConsoleColor.Gray;
            // set up steam API call
            var handle = SteamUGC.StartItemUpdate(RIMWORLD, mod.PublishedFileId);
            setItemAttributes(handle, mod, creating);

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
            OnSteamUGCQueryCompletedCallResult = CallResult<SteamUGCQueryCompleted_t>.Create(OnSteamUGCQueryCompleted);
            OnSteamUGCRequestUGCDetailsResultCallResult =
                CallResult<SteamUGCRequestUGCDetailsResult_t>.Create(OnSteamUGCRequestUGCDetailsResult);


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
                        Console.ForegroundColor = ConsoleColor.White;
                        Console.WriteLine($"{niceStatus} ({Math.Round((double)mod.ModBytes / 1000)} KB)");
                        break;
                    case "Uploading Preview File":
                        Console.ForegroundColor = ConsoleColor.White;
                        Console.WriteLine($"{niceStatus} ({Math.Round((double)mod.PreviewBytes / 1000)} KB)");
                        if (mod.PreviewsBytes.Any())
                        {
                            Console.WriteLine(
                                $"and {mod.Previews.Count} preview-images ({Math.Round((double)mod.PreviewsBytes.Sum() / 1000)} KB)");
                        }

                        break;
                    default:
                        Console.ForegroundColor = ConsoleColor.Gray;
                        Console.WriteLine(niceStatus);
                        break;
                }

                Console.ForegroundColor = ConsoleColor.Gray;
                lastStatus = status.ToString();
            }

            // we have completed!
            if (submitResult.m_eResult != EResult.k_EResultOK)
            {
                Console.ForegroundColor = ConsoleColor.DarkRed;
                Console.WriteLine($"Unexpected result: {submitResult.m_eResult}");
            }

            SteamAPICall_t removeDependencyHandle;
            SteamAPICall_t addDependencyHandle;
            if (creating)
            {
                foreach (var modDependency in mod.Dependencies)
                {
                    Console.ForegroundColor = ConsoleColor.DarkGreen;
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
                    Console.ForegroundColor = ConsoleColor.DarkGreen;
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
                    Console.ForegroundColor = ConsoleColor.DarkGreen;
                    Console.WriteLine("Adding mod to resurrection-collection");
                    addDependencyHandle =
                        SteamUGC.AddDependency(new PublishedFileId_t(1541984105), mod.PublishedFileId);
                }
                else
                {
                    Console.ForegroundColor = ConsoleColor.DarkGreen;
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
            else
            {
                var requestUGCDetailsHandle = SteamUGC.RequestUGCDetails(mod.PublishedFileId, 5);
                OnSteamUGCRequestUGCDetailsResultCallResult.Set(requestUGCDetailsHandle);
                while (dependencyResult.m_details.m_rgchTitle == null)
                {
                    Thread.Sleep(500);
                    SteamAPI.RunCallbacks();
                }

                if (dependencyResult.m_details.m_unNumChildren > 0)
                {
                    Console.WriteLine("Current dependencies defined on Steam, checking mod-dependencies");
                    PublishedFileId_t[] publishedFileIDs = { mod.PublishedFileId };
                    m_UGCQueryHandle =
                        SteamUGC.CreateQueryUGCDetailsRequest(publishedFileIDs, (uint)publishedFileIDs.Length);
                    SteamUGC.SetReturnChildren(m_UGCQueryHandle, true);
                    var createQueryUGCDetailsRequest = SteamUGC.SendQueryUGCRequest(m_UGCQueryHandle);
                    OnSteamUGCQueryCompletedCallResult.Set(createQueryUGCDetailsRequest);
                    while (collectionQueryResult.m_eResult == EResult.k_EResultNone)
                    {
                        Thread.Sleep(500);
                        SteamAPI.RunCallbacks();
                    }

                    var pvecPublishedFileID = new PublishedFileId_t[dependencyResult.m_details.m_unNumChildren];
                    //SteamUGC.SetReturnOnlyIDs(collectionQueryResult.m_handle, true);
                    var success = SteamUGC.GetQueryUGCChildren(collectionQueryResult.m_handle, 0, pvecPublishedFileID,
                        (uint)pvecPublishedFileID.Length);
                    if (!success)
                    {
                        Console.ForegroundColor = ConsoleColor.DarkRed;
                        Console.WriteLine("Failed to iterate mods in dependencies");
                    }
                    else
                    {
                        if (pvecPublishedFileID.Length > 0)
                        {
                            foreach (var publishedFileIdT in pvecPublishedFileID)
                            {
                                if (mod.Dependencies.Contains(publishedFileIdT.m_PublishedFileId))
                                {
                                    Console.ForegroundColor = ConsoleColor.DarkGreen;
                                    Console.WriteLine(
                                        $"Dependency {publishedFileIdT.m_PublishedFileId} correctly defined");
                                    continue;
                                }

                                Console.ForegroundColor = ConsoleColor.DarkRed;
                                Console.WriteLine(
                                    $"Dependency {publishedFileIdT.m_PublishedFileId} not defined in mod, removing it now");
                                removeUGCDependencyResult = new RemoveUGCDependencyResult_t();
                                removeDependencyHandle =
                                    SteamUGC.RemoveDependency(mod.PublishedFileId, publishedFileIdT);
                                OnRemoveUGCDependencyCompletedCallResult.Set(removeDependencyHandle);
                                while (removeUGCDependencyResult.m_eResult == EResult.k_EResultNone)
                                {
                                    Thread.Sleep(5);
                                    SteamAPI.RunCallbacks();
                                }
                            }

                            foreach (var modDependency in mod.Dependencies)
                            {
                                if (pvecPublishedFileID.Any(idt => idt.m_PublishedFileId == modDependency))
                                {
                                    Console.ForegroundColor = ConsoleColor.DarkGreen;
                                    Console.WriteLine($"Dependency {modDependency} correctly defined");
                                    continue;
                                }

                                Console.ForegroundColor = ConsoleColor.DarkRed;
                                Console.WriteLine(
                                    $"Dependency {modDependency} not defined in workshop, adding it now");
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
                        }
                    }

                    Console.ForegroundColor = ConsoleColor.Gray;
                }
                else
                {
                    Console.WriteLine("No current dependencies defined on Steam, checking mod-dependencies");
                    foreach (var modDependency in mod.Dependencies)
                    {
                        Console.ForegroundColor = ConsoleColor.DarkGreen;
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
                }
            }

            if (!mod.Archived)
            {
                return submitResult.m_eResult == EResult.k_EResultOK;
            }

            removeUGCDependencyResult = new RemoveUGCDependencyResult_t();
            if (mod.Name.Contains("(Continued)"))
            {
                Console.ForegroundColor = ConsoleColor.DarkRed;
                Console.WriteLine("Removing mod from resurrection-collection");
                removeDependencyHandle =
                    SteamUGC.RemoveDependency(new PublishedFileId_t(1541984105), mod.PublishedFileId);
            }
            else
            {
                Console.ForegroundColor = ConsoleColor.DarkRed;
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
            if (result.m_eResult != EResult.k_EResultOK)
            {
                Console.ForegroundColor = ConsoleColor.DarkRed;
                Console.WriteLine($"submit callback called:{result.m_eResult} :: {result.m_nPublishedFileId}");
            }

            // store result and let the main thread continue
            submitResult = result;
            ready.Set();
        }

        private static bool create(Mod mod)
        {
            // start async call
            var call = SteamUGC.CreateItem(RIMWORLD, 0);
            createResultCallback = CallResult<CreateItemResult_t>.Create(OnItemCreated);
            createResultCallback.Set(call);

            // keep checking for async call to complete
            while (!ready.WaitOne(500))
            {
                Console.ForegroundColor = ConsoleColor.Gray;
                SteamAPI.RunCallbacks();
                Console.WriteLine("Waiting for item creation to complete.");
            }

            // we have completed!
            if (createResult.m_eResult != EResult.k_EResultOK)
            {
                Console.ForegroundColor = ConsoleColor.DarkRed;
                Console.WriteLine(createResult.m_eResult);
            }
            else
            {
                mod.PublishedFileId = createResult.m_nPublishedFileId;
                Console.ForegroundColor = ConsoleColor.DarkGreen;
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

        private static void setItemAttributes(UGCUpdateHandle_t handle, Mod mod, bool creating)
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

                Console.ForegroundColor = ConsoleColor.White;
                Console.WriteLine($"Adding {mod.Previews.Count} preview images");
            }

            if (!mod.Archived)
            {
                return;
            }

            Console.ForegroundColor = ConsoleColor.White;
            Console.WriteLine("Setting visibility to hidden");
            SteamUGC.SetItemVisibility(handle,
                ERemoteStoragePublishedFileVisibility.k_ERemoteStoragePublishedFileVisibilityUnlisted);
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

        private static void OnSteamUGCQueryCompleted(SteamUGCQueryCompleted_t pCallback, bool bIOFailure)
        {
            collectionQueryResult = pCallback;
        }

        private static void OnSteamUGCRequestUGCDetailsResult(SteamUGCRequestUGCDetailsResult_t pCallback,
            bool bIOFailure)
        {
            dependencyResult = pCallback;
        }

        public static void Shutdown()
        {
            SteamAPI.Shutdown();
            _initialized = false;
        }
    }
}