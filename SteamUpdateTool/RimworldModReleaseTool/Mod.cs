using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Xml;
using System.Xml.Linq;
using Steamworks;
using Version = System.Version;

namespace RimworldModReleaseTool
{
    public class Mod
    {
        public readonly List<string> Tags;
        private PublishedFileId_t _publishedFileId = PublishedFileId_t.Invalid;

        public Mod(string path, string imageFolderPath)
        {
            if (!Directory.Exists(path))
            {
                throw new Exception($"mod-path '{path}' not found.");
            }

            if (!string.IsNullOrEmpty(imageFolderPath) && !Directory.Exists(imageFolderPath))
            {
                throw new Exception($"image-path '{imageFolderPath}' not found.");
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
                        continue;
                    }

                    if (metaNode.Name.ToLower() == "description")
                    {
                        Description = metaNode.InnerText;
                        continue;
                    }

                    if (metaNode.Name == "supportedVersions")
                    {
                        foreach (XmlNode tagNode in metaNode.ChildNodes)
                        {
                            Version.TryParse(tagNode.InnerText, out var version);
                            Tags.Add(version.Major + "." + version.Minor);
                        }
                    }
                }
            }

            Dependencies = new List<ulong>();

            if (XElement.Parse(aboutXml.InnerXml).Element("modDependencies") != null &&
                XElement.Parse(aboutXml.InnerXml).Element("modDependencies").HasElements)
            {
                foreach (var xElement in XElement.Parse(aboutXml.InnerXml).Element("modDependencies")?.Elements())
                {
                    var stringDependency =
                        xElement.Element("steamWorkshopUrl")?.Value.Replace("=", "/").Split('/').Last();
                    try
                    {
                        Dependencies.Add(Convert.ToUInt64(stringDependency));
                    }
                    catch (Exception e)
                    {
                        Console.WriteLine($"Could not convert {stringDependency} to ulong {e}");
                    }
                }
            }

            Console.WriteLine($"Found {Dependencies.Count} dependencies to add. {string.Join(", ", Dependencies)}");
            Archived = Description?.Contains("CN9Rs5X.png") == true;

            // get preview images
            var preview = PathCombine(path, "About", "Preview.png");
            if (File.Exists(preview))
            {
                Preview = preview;
                PreviewBytes = new FileInfo(preview).Length;
            }

            PreviewsBytes = new List<long>();
            Previews = new List<string>();
            if (!string.IsNullOrEmpty(imageFolderPath))
            {
                for (var i = 1; i < 100; i++)
                {
                    var filePath = PathCombine(imageFolderPath, $"{i}.png");
                    if (File.Exists(filePath))
                    {
                        Previews.Add(filePath);
                        PreviewsBytes.Add(new FileInfo(filePath).Length);
                        continue;
                    }

                    filePath = PathCombine(imageFolderPath, $"{i}.jpg");
                    if (File.Exists(filePath))
                    {
                        Previews.Add(filePath);
                        PreviewsBytes.Add(new FileInfo(filePath).Length);
                        continue;
                    }

                    filePath = PathCombine(imageFolderPath, $"{i}.gif");
                    if (File.Exists(filePath))
                    {
                        Previews.Add(filePath);
                        PreviewsBytes.Add(new FileInfo(filePath).Length);
                        continue;
                    }

                    // Console.WriteLine($"Could not find any preview in path {filePath}, will not continue looking");
                    break;
                }
            }

            Console.WriteLine(
                $"Found {Previews.Count} previews to add from {imageFolderPath}. {string.Join(", ", Previews)}");

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
        public List<string> Previews { get; }
        public string Description { get; }
        public long PreviewBytes { get; }
        public List<long> PreviewsBytes { get; }
        public long ModBytes { get; }
        public bool Archived { get; }
        public List<ulong> Dependencies { get; }

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