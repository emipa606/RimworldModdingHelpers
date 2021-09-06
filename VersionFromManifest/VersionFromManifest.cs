using System;
using System.Collections.Generic;
using System.IO;
using Verse;

namespace Mlie
{
    public class VersionFromManifest
    {
        private const string ManifestFileName = "Manifest.xml";

        private List<string> dependencies;
        private string downloadUri;
        private string identifier;
        private List<string> incompatibleWith;
        private List<string> loadAfter;
        private List<string> loadBefore;
        private string manifestUri;
        private string version;

        private static string AboutDir(ModMetaData mod)
        {
            return Path.Combine(mod.RootDir.FullName, "About");
        }

        public static string GetVersionFromModMetaData(ModMetaData modMetaData)
        {
            var manifestPath = Path.Combine(AboutDir(modMetaData), ManifestFileName);
            if (!File.Exists(manifestPath))
            {
                return null;
            }

            try
            {
                var manifest = DirectXmlLoader.ItemFromXmlFile<VersionFromManifest>(manifestPath);
                return manifest.version;
            }
            catch (Exception e)
            {
                Log.ErrorOnce($"Error loading manifest for '{modMetaData.Name}':\n{e.Message}\n\n{e.StackTrace}",
                    modMetaData.Name.GetHashCode());
            }

            return null;
        }
    }
}