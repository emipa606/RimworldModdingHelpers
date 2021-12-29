using System;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.RegularExpressions;
using System.Xml;
using SteamCollectionManager.Properties;

namespace SteamCollectionManager
{
    internal class Program
    {
        private static NameValueCollection modCache;

        public static void Main(string[] args)
        {
            InitializeProgram();
            if (args.Length != 2)
            {
                Console.ForegroundColor = ConsoleColor.DarkRed;
                Console.WriteLine(
                    "First parameter is the id of the collection to manage, second is the path to the save or the id of a mod to add. Remember to remove current mods from collection as this only adds them");
                return;
            }

            var collectionId = args[0];
            if (!Regex.IsMatch(collectionId, @"^\d+$"))
            {
                Console.ForegroundColor = ConsoleColor.DarkRed;
                Console.WriteLine($"Collection id {collectionId} is not numeric");
                return;
            }

            var savePath = args[1];
            if (Regex.IsMatch(savePath, @"^\d+$"))
            {
                Console.ForegroundColor = ConsoleColor.Cyan;
                Console.WriteLine(
                    $"Second parameter {savePath} is numeric, assuming you just want to add it to the collection");
                SteamUtility.JustAddOne(collectionId, savePath);
                return;
            }

            if (!File.Exists(savePath))
            {
                Console.ForegroundColor = ConsoleColor.DarkRed;
                Console.WriteLine($"{savePath} not found");
                return;
            }

            if (!string.IsNullOrEmpty(Settings.Default.RimworldFolder) &&
                !Directory.Exists(Settings.Default.RimworldFolder))
            {
                Settings.Default.RimworldFolder = null;
                Settings.Default.Save();
            }

            if (string.IsNullOrEmpty(Settings.Default.RimworldFolder))
            {
                Console.ForegroundColor = ConsoleColor.Cyan;
                Console.WriteLine("Paste the path to your Rimworld folder: (CTRL+C aborts)");
                var rimworldFolder = Console.ReadLine();

                if (!Directory.Exists(rimworldFolder))
                {
                    Console.ForegroundColor = ConsoleColor.DarkRed;
                    Console.WriteLine($"Could not find {rimworldFolder}");
                    return;
                }

                Settings.Default.RimworldFolder = rimworldFolder;
                Settings.Default.Save();
            }

            var packageIdsToAdd = GetAllIdsToAdd(savePath);
            if (!packageIdsToAdd.Any())
            {
                Console.ForegroundColor = ConsoleColor.DarkRed;
                Console.WriteLine($"Could not parse any mods from {savePath}");
                return;
            }

            Console.ForegroundColor = ConsoleColor.Gray;
            var idsToAdd = new List<string>();
            foreach (var packageId in packageIdsToAdd)
            {
                if (modCache[packageId] == null)
                {
                    Console.ForegroundColor = ConsoleColor.DarkRed;
                    Console.WriteLine($"Could not parse steamId from {packageId}");
                    continue;
                }

                idsToAdd.Add(modCache[packageId]);
            }

            Console.ForegroundColor = ConsoleColor.White;
            Console.WriteLine($"{idsToAdd.Count} steamIds matched");

            Console.ForegroundColor = ConsoleColor.Cyan;
            Console.WriteLine("Continue? (CTRL+C aborts)");
            Console.ReadLine();
            Console.ForegroundColor = ConsoleColor.Gray;

            SteamUtility.SyncCollection(collectionId, idsToAdd);
        }

        private static List<string> GetAllIdsToAdd(string savePath)
        {
            var foundIds = new List<string>();
            try
            {
                var doc = new XmlDocument();
                doc.Load(savePath);
                var nodes = doc.ChildNodes[1].ChildNodes[0].ChildNodes[1].ChildNodes;
                foreach (XmlNode node in nodes)
                {
                    if (node.InnerText.StartsWith("ludeon."))
                    {
                        continue;
                    }

                    foundIds.Add(node.InnerText);
                }
            }
            catch (Exception exception)
            {
                Console.ForegroundColor = ConsoleColor.DarkRed;
                Console.WriteLine($"Failed to parse save-file: {exception}");
                return foundIds;
            }

            UpdateCache();

            return foundIds;
        }

        private static void UpdateCache()
        {
            var steamFolder = $"{Settings.Default.RimworldFolder}\\..\\..\\workshop\\content\\294100";
            var localFolder = $"{Settings.Default.RimworldFolder}\\Mods";
            modCache = new NameValueCollection();

            var steamMods = Directory.GetDirectories(steamFolder);
            var localMods = Directory.GetDirectories(localFolder);

            Console.ForegroundColor = ConsoleColor.Gray;
            Console.WriteLine($"Caching mod-ids of {steamMods.Length + localMods.Length} mods");
            foreach (var mod in steamMods)
            {
                ParseModFolder(mod);
            }

            foreach (var mod in localMods)
            {
                ParseModFolder(mod);
            }

            Console.ForegroundColor = ConsoleColor.Gray;
            Console.WriteLine($"Cached {modCache.Count} mod-ids");
        }

        private static void ParseModFolder(string folderPath)
        {
            var aboutFile = $"{folderPath}\\About\\About.xml";
            var publishedIdFile = $"{folderPath}\\About\\PublishedFileId.txt";

            if (!File.Exists(publishedIdFile) || !File.Exists(aboutFile))
            {
                return;
            }

            var publishedId = File.ReadAllText(publishedIdFile);
            string packageId = null;
            try
            {
                var doc = new XmlDocument();
                doc.Load(aboutFile);
                foreach (XmlNode node in doc.ChildNodes)
                {
                    if (node.Name != "ModMetaData")
                    {
                        continue;
                    }

                    foreach (XmlNode nodeChildNode in node.ChildNodes)
                    {
                        if (nodeChildNode.Name != "packageId")
                        {
                            continue;
                        }

                        packageId = nodeChildNode.InnerText;
                        break;
                    }
                }
            }
            catch (Exception)
            {
                Console.ForegroundColor = ConsoleColor.Yellow;
                Console.WriteLine($"Failed to parse mod-file at {folderPath}");
                return;
            }

            if (string.IsNullOrEmpty(packageId))
            {
                Console.ForegroundColor = ConsoleColor.Yellow;
                Console.WriteLine($"Could not find a packageId for {folderPath}");
                return;
            }

            if (string.IsNullOrEmpty(publishedId))
            {
                Console.ForegroundColor = ConsoleColor.Yellow;
                Console.WriteLine($"Could not find a publishedId for {folderPath}");
            }

            if (modCache[packageId] != null)
            {
                return;
            }

            modCache.Add(packageId, publishedId);
        }

        private static void InitializeProgram()
        {
            AppDomain.CurrentDomain.AssemblyResolve += (sender, args) =>
            {
                var resourceName = "AssemblyLoadingAndReflection." +
                                   new AssemblyName(args.Name).Name + ".dll";
                using (var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(resourceName))
                {
                    if (stream == null)
                    {
                        return null;
                    }

                    var assemblyData = new byte[stream.Length];
                    stream.Read(assemblyData, 0, assemblyData.Length);
                    return Assembly.Load(assemblyData);
                }
            };
        }
    }
}