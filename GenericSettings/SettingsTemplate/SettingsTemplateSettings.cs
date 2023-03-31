using Verse;

namespace SettingsTemplate
{
    /// <summary>
    ///     Definition of the settings for the mod
    /// </summary>
    internal class SettingsTemplateSettings : ModSettings
    {
        public bool CheckboxValue = true;
        public float FloatValue = 5f;
        public IntRange IntRangeValue = new IntRange(10, 20);
        public int IntValue = 3;

        /// <summary>
        ///     Saving and loading the values
        /// </summary>
        public override void ExposeData()
        {
            base.ExposeData();
            Scribe_Values.Look(ref CheckboxValue, "CheckboxValue", true);
            Scribe_Values.Look(ref IntValue, "IntValue", 3);
            Scribe_Values.Look(ref IntRangeValue, "IntRangeValue", new IntRange(10, 20));
            Scribe_Values.Look(ref FloatValue, "FloatValue", 5f);
        }
    }
}