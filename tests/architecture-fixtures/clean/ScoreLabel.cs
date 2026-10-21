using Godot;

// Every rule's good counterpart: references found once, events unsubscribed, nothing allocated per frame.
public partial class ScoreLabel : Label
{
    private Node2D _player;
    private int _shown = -1;
    private static readonly StringName Pause = "pause";

    public override void _Ready()
    {
        _player = GetNode<Node2D>("../Player");
        Events.Instance.ScoreChanged += OnScoreChanged;
    }

    public override void _ExitTree() => Events.Instance.ScoreChanged -= OnScoreChanged;

    public override void _Process(double delta)
    {
        Visible = _player.Visible && !Input.IsActionPressed(Pause);
    }

    private void OnScoreChanged(int score)
    {
        if (score == _shown) return;
        _shown = score;
        Text = score.ToString();
    }
}
