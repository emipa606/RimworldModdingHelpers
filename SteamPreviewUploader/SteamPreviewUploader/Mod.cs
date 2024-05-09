using System;
using System.IO;
using Steamworks;

namespace RimworldModReleaseTool
{
    public class Mod
    {
        public Mod(string path, string imagePath, uint index)
        {
            if (!Directory.Exists(path))
            {
                throw new Exception($"mod-path '{path}' not found.");
            }

            if (string.IsNullOrEmpty(imagePath) || !File.Exists(imagePath))
            {
                throw new Exception($"image-path '{imagePath}' not found.");
            }

            PreviewIndex = index;
            Preview = imagePath;
            PreviewBytes = new FileInfo(imagePath).Length;

            // get publishedFileId
            var pubfileIdPath = PathCombine(path, "About", "PublishedFileId.txt");
            if (File.Exists(pubfileIdPath) && uint.TryParse(File.ReadAllText(pubfileIdPath), out var id))
            {
                PublishedFileId = new PublishedFileId_t(id);
            }
            else
            {
                throw new Exception("PublishedFileId.txt not found, needs to be published first.");
            }
        }

        public uint PreviewIndex { get; }
        public string Preview { get; }
        public long PreviewBytes { get; }

        public PublishedFileId_t PublishedFileId { get; set; }

        public override string ToString()
        {
            return
                $"Preview: {Preview}\nPublishedFileId: {PublishedFileId}\nPreviewIndex: {PreviewIndex}";
        }

        private static string PathCombine(params string[] parts)
        {
            return string.Join(Path.DirectorySeparatorChar.ToString(), parts);
        }
    }
}