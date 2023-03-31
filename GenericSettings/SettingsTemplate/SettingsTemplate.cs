using Verse;

namespace SettingsTemplate;

[StaticConstructorOnStartup]
public static class SettingsTemplate
{
	static SettingsTemplate()
	{
		new Harmony("Mlie.SettingsTemplate").PatchAll(Assembly.GetExecutingAssembly());
		Log.Message($"CheckboxValue: {SettingsTemplateMod.instance.Settings.CheckboxValue}");
		Log.Message($"IntValue: {SettingsTemplateMod.instance.Settings.IntValue}");
		Log.Message($"IntRangeValue: {SettingsTemplateMod.instance.Settings.IntRangeValue}");
		Log.Message($"Floatvalue: {SettingsTemplateMod.instance.Settings.FloatValue}");
	}
}