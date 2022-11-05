using System.Linq;
using System.Reflection;
using Verse;

namespace Mlie;

[StaticConstructorOnStartup]
public static class Main
{
    static Main()
    {
        return;

        // Not working
        var allModsToUpdate =
            ModLister.AllInstalledMods.Where(mod => mod.PackageId.ToLower().StartsWith("mlie") &&
                                                    string.IsNullOrEmpty(mod.ModVersion) &&
                                                    VersionFromManifest.TryGetManifestFile(mod,
                                                        out _));

        if (!allModsToUpdate.Any())
        {
            return;
        }


        var metaDataField = typeof(ModMetaData).GetField("meta", BindingFlags.NonPublic | BindingFlags.Instance);

        if (metaDataField == null)
        {
            Log.Message("metaDataField is null");
            return;
        }

        var modVersionField =
            metaDataField.FieldType.GetField("modVersion", BindingFlags.Public | BindingFlags.Instance);

        if (modVersionField == null)
        {
            Log.Message("modVersionField is null");
            return;
        }

        var modCacheField = typeof(ModsConfig).GetField("activeModsInLoadOrderCachedDirty",
            BindingFlags.NonPublic | BindingFlags.Static);
        if (modCacheField == null)
        {
            Log.Message("modCacheField is null");
            return;
        }


        foreach (var modWithNoVersion in allModsToUpdate)
        {
            var foundVersion = VersionFromManifest.GetVersionFromModMetaData(modWithNoVersion);
            if (string.IsNullOrEmpty(foundVersion))
            {
                continue;
            }

            if (Prefs.DevMode)
            {
                Log.Message($"Setting version {foundVersion} for mod {modWithNoVersion.Name}");
            }

            var internalModMetaData = metaDataField.GetValue(modWithNoVersion);

            modVersionField.SetValue(internalModMetaData, foundVersion);

            metaDataField.SetValue(modWithNoVersion, internalModMetaData);

            modCacheField.SetValue(typeof(ModsConfig), true);

            Log.Message(modWithNoVersion.ModVersion);
        }
    }
}