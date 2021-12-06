using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;
using Steamworks;

namespace SteamCollectionManager
{
    public static class SteamUtility
    {
        private const int RIMWORLD_APP_INT = 294100;
        private static bool _initialized;
        private static PublishedFileId_t lastModInCollection;

        private static UGCQueryHandle_t m_UGCQueryHandle;
        private static CallResult<SteamUGCQueryCompleted_t> OnSteamUGCQueryCompletedCallResult;
        private static CallResult<RemoveUGCDependencyResult_t> OnRemoveUGCDependencyCompletedCallResult;
        private static CallResult<AddUGCDependencyResult_t> OnAddUGCDependencyCompletedCallResult;
        private static CallResult<SteamUGCRequestUGCDetailsResult_t> OnSteamUGCRequestUGCDetailsResultCallResult;
        private static SteamUGCRequestUGCDetailsResult_t collectionResult;
        private static SteamUGCQueryCompleted_t collectionQueryResult;
        private static RemoveUGCDependencyResult_t removeUGCDependencyResult;
        private static AddUGCDependencyResult_t addUGCDependencyResult;

        public static void SyncCollection(string collectionId, List<string> idsToAdd)
        {
            if (!Init())
            {
                Console.ForegroundColor = ConsoleColor.DarkRed;
                Console.WriteLine("Failed to init");
                return;
            }

            lastModInCollection = PublishedFileId_t.Invalid;
            collectionQueryResult = new SteamUGCQueryCompleted_t();
            collectionResult = new SteamUGCRequestUGCDetailsResult_t();
            var collectionFileId = new PublishedFileId_t(Convert.ToUInt64(collectionId));

            OnSteamUGCQueryCompletedCallResult = CallResult<SteamUGCQueryCompleted_t>.Create(OnSteamUGCQueryCompleted);
            OnRemoveUGCDependencyCompletedCallResult =
                CallResult<RemoveUGCDependencyResult_t>.Create(OnRemoveUGCDependencyCompleted);
            OnAddUGCDependencyCompletedCallResult =
                CallResult<AddUGCDependencyResult_t>.Create(OnAddUGCDependencyCompleted);

            OnSteamUGCRequestUGCDetailsResultCallResult =
                CallResult<SteamUGCRequestUGCDetailsResult_t>.Create(OnSteamUGCRequestUGCDetailsResult);
            var requestUGCDetailsHandle = SteamUGC.RequestUGCDetails(collectionFileId, 5);
            OnSteamUGCRequestUGCDetailsResultCallResult.Set(requestUGCDetailsHandle);

            while (collectionResult.m_details.m_rgchTitle == null)
            {
                Thread.Sleep(500);
                SteamAPI.RunCallbacks();
            }

            if (collectionResult.m_details.m_unNumChildren > 0)
            {
                Console.ForegroundColor = ConsoleColor.Yellow;
                Console.WriteLine(
                    $"Collection {collectionResult.m_details.m_rgchTitle} have {collectionResult.m_details.m_unNumChildren} mods. If you continue they will be removed from the collection first.");
                Console.ForegroundColor = ConsoleColor.Cyan;
                Console.WriteLine("Continue? (CTRL+C aborts)");
                Console.ReadLine();
                Console.ForegroundColor = ConsoleColor.Gray;

                PublishedFileId_t[] publishedFileIDs = { collectionFileId };
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

                var pvecPublishedFileID = new PublishedFileId_t[collectionResult.m_details.m_unNumChildren];
                //SteamUGC.SetReturnOnlyIDs(collectionQueryResult.m_handle, true);
                var success = SteamUGC.GetQueryUGCChildren(collectionQueryResult.m_handle, 0, pvecPublishedFileID,
                    (uint)pvecPublishedFileID.Length);
                if (!success)
                {
                    Console.ForegroundColor = ConsoleColor.DarkRed;
                    Console.WriteLine("Failed to iterate mods in collection");
                    return;
                }

                Console.ForegroundColor = ConsoleColor.Gray;
                Console.WriteLine(
                    $"Removing existing {collectionResult.m_details.m_unNumChildren} mods from collection");
                // Collections cannot have zero items, leaving the first item
                lastModInCollection = pvecPublishedFileID[pvecPublishedFileID.Length - 1];
                using (var progress = new ProgressBar())
                {
                    for (var index = 0; index < pvecPublishedFileID.Length - 1; index++)
                    {
                        progress.Report((double)index / pvecPublishedFileID.Length);
                        var publishedFileIdT = pvecPublishedFileID[index];
                        removeUGCDependencyResult = new RemoveUGCDependencyResult_t();
                        var removeDependencyHandle = SteamUGC.RemoveDependency(collectionFileId, publishedFileIdT);
                        OnRemoveUGCDependencyCompletedCallResult.Set(removeDependencyHandle);
                        while (removeUGCDependencyResult.m_eResult == EResult.k_EResultNone)
                        {
                            Thread.Sleep(5);
                            SteamAPI.RunCallbacks();
                        }

                        if (removeUGCDependencyResult.m_eResult == EResult.k_EResultOK)
                        {
                            continue;
                        }

                        Console.ForegroundColor = ConsoleColor.Yellow;
                        Console.WriteLine(
                            $"Removal of {publishedFileIdT.m_PublishedFileId} failed: {removeUGCDependencyResult.m_eResult}");
                    }
                }
            }

            Console.ForegroundColor = ConsoleColor.Gray;
            Console.WriteLine("Removed all but one mod (as collections needs to have at least one)");
            Console.ForegroundColor = ConsoleColor.Cyan;
            Console.WriteLine("Continue? (CTRL+C aborts)");
            Console.ReadLine();
            Console.ForegroundColor = ConsoleColor.Gray;
            Console.WriteLine($"Adding {idsToAdd.Count} mods to collection");
            try
            {
                var indexToStartFrom = 0;
                if (lastModInCollection.m_PublishedFileId.ToString() == idsToAdd[0])
                {
                    indexToStartFrom = 1;
                }

                using (var progress = new ProgressBar())
                {
                    for (var index = indexToStartFrom; index < idsToAdd.Count; index++)
                    {
                        progress.Report((double)index / idsToAdd.Count);
                        var id = idsToAdd[index];
                        //Console.WriteLine(id);
                        var modFileId = new PublishedFileId_t(Convert.ToUInt64(id));
                        addUGCDependencyResult = new AddUGCDependencyResult_t();
                        var addDependencyHandle = SteamUGC.AddDependency(collectionFileId, modFileId);
                        OnAddUGCDependencyCompletedCallResult.Set(addDependencyHandle);
                        while (addUGCDependencyResult.m_eResult == EResult.k_EResultNone)
                        {
                            Thread.Sleep(5);
                            SteamAPI.RunCallbacks();
                        }

                        // Removing the previous left mod if it was not already the first
                        if (index == 0 && lastModInCollection != PublishedFileId_t.Invalid)
                        {
                            SteamUGC.RemoveDependency(collectionFileId, lastModInCollection);
                        }
                    }
                }
            }
            catch (Exception exception)
            {
                Console.ForegroundColor = ConsoleColor.DarkRed;
                Console.WriteLine("Error while adding dependency: ");
                Console.Write(exception.Message);
            }

            Console.ForegroundColor = ConsoleColor.DarkGreen;
            Console.WriteLine("Done!");
            Process.Start($"https://steamcommunity.com/sharedfiles/filedetails/?id={collectionId}");
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

        private static void OnSteamUGCQueryCompleted(SteamUGCQueryCompleted_t pCallback, bool bIOFailure)
        {
            collectionQueryResult = pCallback;
        }

        private static void OnRemoveUGCDependencyCompleted(RemoveUGCDependencyResult_t pCallback, bool bIOFailure)
        {
            removeUGCDependencyResult = pCallback;
        }

        private static void OnAddUGCDependencyCompleted(AddUGCDependencyResult_t pCallback, bool bIOFailure)
        {
            addUGCDependencyResult = pCallback;
        }

        private static void OnSteamUGCRequestUGCDetailsResult(SteamUGCRequestUGCDetailsResult_t pCallback,
            bool bIOFailure)
        {
            collectionResult = pCallback;
        }
    }
}