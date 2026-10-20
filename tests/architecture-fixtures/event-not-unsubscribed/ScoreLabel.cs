using Godot;

public partial class ScoreLabel : Node
{
    public override void _Ready()
    {
        Events.Instance.ScoreChanged += OnScoreChanged;
    }

    private void OnScoreChanged(int score) { }
}
