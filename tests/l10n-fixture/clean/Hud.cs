using Godot;
public partial class Hud : Label
{
    public override void _Ready() => Text = Tr("SCORE");
}
