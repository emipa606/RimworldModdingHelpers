using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Xml;
using System.Xml.Linq;

namespace RimworldModReleaseTool
{
    public class ModUpdateInfo
    {
        public ModUpdateInfo(string modRootFolder)
        {
            Path = modRootFolder;

            var steamPublishIDPath = Path + @"\About\PublishedFileId.txt";
            if (File.Exists(steamPublishIDPath))
            {
                var steamPublishID = File.ReadLines(steamPublishIDPath).First();
                SteamURL = @"https://steamcommunity.com/sharedfiles/filedetails/?id=" + steamPublishID;
            }

            ///// Get the name
            var modName = ParseAboutXMLFor("name", Path);
            var modAuthor = ParseAboutXMLFor("author", Path);

            Name = modName; //path.Substring(path.LastIndexOf("\\", StringComparison.Ordinal) + 1);
            Author = modAuthor;

            var changelogPath = Path + @"\About\Changelog.txt";
            var manifestPath = Path + @"\About\Manifest.xml";

            var changelogFile = new FileInfo(changelogPath);
            var manifestFile = new FileInfo(manifestPath);
            if (!changelogFile.Exists || !manifestFile.Exists)
            {
                return;
            }

            string currentVersion = null;
            foreach (var line in File.ReadAllLines(manifestFile.FullName))
            {
                if (!line.Contains("<version>"))
                {
                    continue;
                }

                currentVersion = line.Replace("<version>", "|").Split('|')[1].Split('<')[0];
            }

            if (string.IsNullOrEmpty(currentVersion))
            {
                return;
            }

            var isExtracting = false;
            var changelogArray = new List<string>();
            var versionRegex = new Regex(@"\d+(?:\.\d+){1,3}");
            foreach (var line in File.ReadAllLines(changelogFile.FullName))
            {
                if (line.StartsWith(currentVersion))
                {
                    isExtracting = true;
                    changelogArray.Add(line);
                    continue;
                }

                var match = versionRegex.Match(line);
                if (!isExtracting)
                {
                    continue;
                }

                if (match.Success)
                {
                    break;
                }

                changelogArray.Add(line);
            }

            var changelogMessage = string.Join(Environment.NewLine, changelogArray).Trim();

            LatestChangeNote = changelogMessage;
        }


        public string Path { get; }

        public string Name { get; }

        public string Author { get; }

        public string SteamURL { get; }

        public string LatestChangeNote { get; }


        private static string ParseAboutXMLFor(string element, string newPath)
        {
            var text = newPath + @"\About\About.xml";
            var xml = new XmlDocument();
            xml.Load(text);
            return XElement.Parse(xml.InnerXml).Element(element)?.Value ?? "NULL";
        }
    }
}