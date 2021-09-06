using System;
using System.Collections.Generic;
using System.IO;
using System.Xml;
using Steamworks;
using Version = System.Version;

namespace RimworldModReleaseTool
{
    public class Mod
    {
        public readonly List<string> Tags;
        private PublishedFileId_t _publishedFileId = PublishedFileId_t.Invalid;

        public Mod(string path)
        {
            if (!Directory.Exists(path))
            {
                throw new Exception($"path '{path}' not found.");
            }

            var about = PathCombine(path, "About", "About.xml");
            if (!File.Exists(about))
            {
                throw new Exception($"About.xml not found at ({about})");
            }

            ContentFolder = path;
            ModBytes = GetFolderSize(ContentFolder);

            Tags = new List<string>
            {
                "Mod"
            };

            // open About.xml
            var aboutXml = new XmlDocument();
            aboutXml.Load(about);
            foreach (XmlNode node in aboutXml.ChildNodes)
            {
                if (node.Name != "ModMetaData")
                {
                    continue;
                }

                foreach (XmlNode metaNode in node.ChildNodes)
                {
                    if (metaNode.Name.ToLower() == "name")
                    {
                        Name = metaNode.InnerText;
                    }

                    if (metaNode.Name.ToLower() == "description")
                    {
                        Description = metaNode.InnerText;
                    }

                    if (metaNode.Name != "supportedVersions")
                    {
                        continue;
                    }

                    foreach (XmlNode tagNode in metaNode.ChildNodes)
                    {
                        Version.TryParse(tagNode.InnerText, out var version);
                        Tags.Add(version.Major + "." + version.Minor);
                    }
                }
            }

            Archived = Description?.Contains("CN9Rs5X.png") == true;

            // get preview image
            var preview = PathCombine(path, "About", "Preview.png");
            if (File.Exists(preview))
            {
                Preview = preview;
                PreviewBytes = new FileInfo(preview).Length;
            }

            // get publishedFileId
            var pubfileIdPath = PathCombine(path, "About", "PublishedFileId.txt");
            if (File.Exists(pubfileIdPath) && uint.TryParse(File.ReadAllText(pubfileIdPath), out var id))
            {
                PublishedFileId = new PublishedFileId_t(id);
            }
            else
            {
                PublishedFileId = PublishedFileId_t.Invalid;
            }
        }

        public string Name { get; }
        public string Preview { get; }
        public string Description { get; }
        public long PreviewBytes { get; }
        public long ModBytes { get; }
        public bool Archived { get; }


        public PublishedFileId_t PublishedFileId
        {
            get => _publishedFileId;
            set
            {
                if (_publishedFileId != value && value != PublishedFileId_t.Invalid)
                {
                    File.WriteAllText(PathCombine(ContentFolder, "About", "PublishedFileId.txt"),
                        value.ToString().Trim());
                }

                _publishedFileId = value;
            }
        }

        public string ContentFolder { get; }

        public override string ToString()
        {
            return
                $"Name: {Name}\nPreview: {Preview}\nPublishedFileId: {PublishedFileId}\nTags: {string.Join(",", Tags)}"; // \nDescription: {Description}";
        }

        private static long GetFolderSize(string folderPath)
        {
            var allFilesAndFolders = Directory.GetFiles(folderPath, "*.*", SearchOption.AllDirectories);
            long returnValue = 0;
            foreach (var name in allFilesAndFolders)
            {
                var info = new FileInfo(name);
                returnValue += info.Length;
            }

            return returnValue;
        }

        private static string PathCombine(params string[] parts)
        {
            return string.Join(Path.DirectorySeparatorChar.ToString(), parts);
        }
    }
}