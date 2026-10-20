using Godot;

public partial class Hud : Node
{
    private int _score;

    public override void _Process(double delta)
    {
        GD.Print($"Score {_score}");
    }
}
