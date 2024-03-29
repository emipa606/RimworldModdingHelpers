﻿using System;
using System.Collections.Generic;
using System.IO;
using Verse;

namespace Mlie;

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
    private bool showCrossPromotions;
    private List<string> suggests;
    private List<string> targetVersions;
    private string version;

    public static bool TryGetManifestFile(ModMetaData mod, out string filePath)
    {
        filePath = Path.Combine(Path.Combine(mod.RootDir.FullName, "About"), ManifestFileName);
        return File.Exists(filePath);
    }

    public static string GetVersionFromModMetaData(ModMetaData modMetaData)
    {
        if (!TryGetManifestFile(modMetaData, out var manifestPath))
        {
            return null;
        }

        try
        {
            var manifest = DirectXmlLoader.ItemFromXmlFile<VersionFromManifest>(manifestPath, false);
            return manifest.version;
        }
        catch (Exception e)
        {
            if (Prefs.DevMode)
            {
                Log.ErrorOnce($"Error loading manifest for '{modMetaData.Name}':\n{e.Message}\n\n{e.StackTrace}",
                    modMetaData.Name.GetHashCode());
            }
        }

        return null;
    }
}