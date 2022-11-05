using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using RimWorld;
using UnityEngine;
using Verse;

namespace Mlie;

[StaticConstructorOnStartup]
public static class ModMenu
{
    private static string searchText;
    private static readonly Vector2 searchSize = new Vector2(200f, 25f);
    private static readonly Vector2 previewImage = new Vector2(179f, 100f);

    public static readonly List<Mod> AllMyModsList;

    static ModMenu()
    {
        searchText = "";
        AllMyModsList = LoadedModManager.ModHandles.Where(mod =>
                mod.Content.PackageId.ToLower().StartsWith("mlie") && string.IsNullOrEmpty(mod.SettingsCategory()))
            .OrderBy(mod => mod.Content.Name).ToList();

        if (DefDatabase<OptionCategoryDef>.GetNamedSilentFail("MliesModsOptionCategoryDef") != null)
        {
            return;
        }

        var metaDataInternalReference = typeof(ModMetaData).Assembly.GetType("ModMetaDataInternal");
        Log.Message($"{metaDataInternalReference}");
        var modVersionField =
            metaDataInternalReference?.GetField("modVersion", BindingFlags.Instance & BindingFlags.NonPublic);

        foreach (var modWithNoVersion in AllMyModsList)
        {
            var foundVersion = VersionFromManifest.GetVersionFromModMetaData(modWithNoVersion.Content.ModMetaData);
            if (string.IsNullOrEmpty(foundVersion))
            {
                Log.Message($"No version found for mod {modWithNoVersion.Content.ModMetaData.Name}");
                continue;
            }

            Log.Message($"Setting version {foundVersion} for mod {modWithNoVersion.Content.ModMetaData.Name}");
            modVersionField?.SetValue(modVersionField, foundVersion);
        }

        var categoryDef = new OptionCategoryDef
        {
            defName = "MliesModsOptionCategoryDef",
            label = "Mods by Mlie",
            description = "All mods published by Mlie",
            modContentPack = AllMyModsList[0].Content,
            texPath = "MliesMods"
        };

        DefGenerator.AddImpliedDef(categoryDef);
    }

    public static void ListMods(ref Listing_Standard listingStandard)
    {
        if (listingStandard.CurHeight > 12)
        {
            return;
        }

        var headerRect = listingStandard.GetRect(searchSize.y);
        Widgets.Label(headerRect, "Search");
        var modsToList = AllMyModsList;

        searchText =
            Widgets.TextField(
                new Rect(
                    headerRect.position +
                    new Vector2(headerRect.width - searchSize.x, 0),
                    searchSize),
                searchText);
        TooltipHandler.TipRegion(new Rect(
            headerRect.position + new Vector2(headerRect.width - searchSize.x, 0),
            searchSize), "Search");

        if (!string.IsNullOrEmpty(searchText))
        {
            modsToList = modsToList.Where(mod => mod.Content.Name.ToLower().Contains(searchText.ToLower())).ToList();
        }

        var yPos = headerRect.y + searchSize.y + 12f;
        listingStandard.GapLine();
        foreach (var mod in modsToList)
        {
            listingStandard.GetRect(previewImage.y);
            var rowRect = new Rect(new Vector2(0, yPos), new Vector2(headerRect.width, previewImage.y));
            if (Mouse.IsOver(rowRect))
            {
                Widgets.DrawOptionUnselected(rowRect);
            }

            Widgets.DrawHighlightIfMouseover(rowRect);

            var textRect = new Rect(previewImage.x + 5f, yPos + 15f, headerRect.width, 25f);
            Widgets.Label(textRect, mod.Content.Name.Truncate(textRect.width));
            if (Text.CalcSize(mod.Content.Name).x > textRect.width)
            {
                Widgets.DrawHighlightIfMouseover(textRect);
                TooltipHandler.TipRegion(textRect, new TipSignal(mod.Content.Name));
            }

            Text.Font = GameFont.Tiny;
            Widgets.Label(new Rect(previewImage.x + 5f, yPos + 35f, headerRect.width, 25f),
                $"Version: {mod.Content.ModMetaData.ModVersion}");
            Widgets.Label(new Rect(previewImage.x + 5f, yPos + 50f, headerRect.width, 25f),
                $"Updated: {VersionFromManifest.GetUpdatedFromModMetaData(mod.Content.ModMetaData)}");
            if (mod.Content.ModMetaData.AuthorsString != "Mlie")
            {
                Widgets.Label(new Rect(previewImage.x + 5f, yPos + 65f, headerRect.width, 25f),
                    $"Original autor: {mod.Content.ModMetaData.AuthorsString}");
            }

            if (Widgets.ButtonInvisible(rowRect))
            {
                Find.WindowStack.Add(new Dialog_SubModWindow(mod));
            }

            Text.Font = GameFont.Small;
            Widgets.DrawTextureFitted(new Rect(new Vector2(0, yPos), previewImage).ContractedBy(1f),
                mod.Content.ModMetaData.PreviewImage, 1f);
            yPos += previewImage.y;
        }
    }
}