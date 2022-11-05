using UnityEngine;
using Verse;

namespace Mlie;

public class Dialog_SubModWindow : Window
{
    private readonly Mod selMod;

    public Dialog_SubModWindow(Mod mod)
    {
        forcePause = true;
        doCloseX = true;
        doCloseButton = true;
        closeOnClickedOutside = true;
        absorbInputAroundWindow = true;
        selMod = mod;
    }

    public override Vector2 InitialSize => new Vector2(864f, 584f);

    public override void PreClose()
    {
        base.PreClose();
        selMod?.WriteSettings();
    }

    public override void DoWindowContents(Rect inRect)
    {
        Text.Font = GameFont.Medium;
        Widgets.Label(new Rect(0f, 0f, inRect.width, 35f), selMod.Content.Name);
        Text.Font = GameFont.Small;
        var inRect2 = new Rect(0f, 40f, inRect.width, inRect.height - 40f - CloseButSize.y);
        selMod.DoSettingsWindowContents(inRect2);
    }
}