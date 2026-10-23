namespace OrbitPatrol;

using Godot;

/// <summary>What the game-over and victory screens share: the run's score, the best, and the way back to the menu.</summary>
public abstract partial class ResultScreen : Control
{
    [Signal]
    public delegate void MenuPressedEventHandler();

    protected int Points { get; private set; }
    protected int Best { get; private set; }

    public void Setup(int points, int best)
    {
        Points = points;
        Best = best;
    }

    public override void _Ready()
    {
        GetNode<Button>("Box/MenuButton").Pressed += () => EmitSignal(SignalName.MenuPressed);
        RefreshText();
    }

    public override void _Notification(int what)
    {
        if (what == NotificationTranslationChanged && IsNodeReady())
            RefreshText();
    }

    protected abstract void RefreshText();
}
