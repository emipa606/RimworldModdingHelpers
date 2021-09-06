# Version from manifest

A support-file to fetch the current version in the About/Manifest.xml file and display it in game, usually in the settings-menu.
Uses the mod-identifier to look up the correct file

Example.

```
private static string currentVersion;
currentVersion = VersionFromManifest.GetVersionFromModMetaData(ModLister.GetActiveModWithIdentifier("ModIdentifier"));
if (currentVersion != null)
{
	listing_Standard.Gap();
	GUI.contentColor = Color.gray;
	listing_Standard.Label("CurrentModVersion_Label".Translate(currentVersion));
	listing_Standard.Label($"Installed mod-version: {currentVersion}");
	GUI.contentColor = Color.white;
}
```