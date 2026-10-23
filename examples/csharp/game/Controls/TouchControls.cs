namespace Example.Controls;

using Example.Core.Controls;
using Godot;

/// <summary>
/// On-screen controls for touchscreens: Example.Core's hit pads (<see cref="TouchPadLayout"/>, <see cref="TouchPadInput"/>)
/// pressing the game's own actions, so keyboard, controller and touch all reach the same <c>Input.GetAxis</c>. Main adds
/// it when <c>DisplayServer.IsTouchscreenAvailable()</c>. It draws only the button art, fading; the pads are invisible.
/// </summary>
public partial class TouchControls : Node2D
{
    static readonly Color ArtColour = new(1, 1, 1, 0.5f);

    private readonly TouchPadInput _fingers = new(new TouchPadLayout());
    private double _playing;
    private float _alpha = -1;

    public TouchPadInput Fingers => _fingers;
    public ButtonFade Fade { get; set; } = new();

    public TouchPadLayout Layout
    {
        get => _fingers.Layout;
        set { _fingers.Layout = value; QueueRedraw(); }
    }

    /// <summary>
    /// Breakout's two pads in its 640x480 viewport: move_left under the left thumb, move_right under the right, the
    /// line at y 360 (the bricks and ball stay above the thumbs). Each pad reaches the middle of the screen, so the band
    /// below the line has no dead spot. On a compact screen the art is drawn smaller and closer to the corners.
    /// </summary>
    public static TouchPadLayout ForBreakout(Vector2 viewport, bool compact, float padScale = 1)
    {
        float inset = compact ? 56 : 80, art = compact ? 28 : 40, line = viewport.Y * 0.75f;
        // From a corner pad to the farther end of the band's middle line, so the two pads meet and cover the band.
        float reach = Mathf.Max(Mathf.Sqrt(Sq(viewport.X / 2 - inset) + Sq(viewport.Y - inset - line)), Mathf.Sqrt(Sq(viewport.X / 2 - inset) + Sq(inset))) + 8;
        return new TouchPadLayout
        {
            LineY = line,
            PadScale = padScale,
            Pads = new[]
            {
                new TouchPad("move_left", new System.Numerics.Vector2(inset, viewport.Y - inset), reach, art),
                new TouchPad("move_right", new System.Numerics.Vector2(viewport.X - inset, viewport.Y - inset), reach, art),
            },
        };
    }

    /// <summary>The layout for the screen this runs on: compact under 7 inches, where the two thumbs can meet.</summary>
    public static TouchPadLayout ForThisScreen(Vector2 viewport, float padScale = 1)
    {
        Vector2I screen = DisplayServer.ScreenGetSize();
        bool compact = TouchPadLayout.IsCompactScreen(new System.Numerics.Vector2(screen.X, screen.Y), DisplayServer.ScreenGetDpi());
        return ForBreakout(viewport, compact, padScale);
    }

    public override void _Ready()
    {
        _fingers.Pressed += Press;
        _fingers.Released += Release;
    }

    public override void _ExitTree() => _fingers.ReleaseAll();   // a freed control must not leave an action held

    public override void _Notification(int what)
    {
        // The fingers are gone without lift events; on resume the art shows again.
        if (what is (int)NotificationApplicationPaused or (int)NotificationApplicationFocusOut)
        {
            _fingers.ReleaseAll();
            _playing = 0;
        }
    }

    public override void _Input(InputEvent e)
    {
        bool mine = e switch
        {
            InputEventScreenTouch { Pressed: true } t => _fingers.Down(t.Index, ToCore(t.Position)),
            InputEventScreenTouch t => _fingers.Up(t.Index),   // a lift, or a cancel (the system took the touch)
            InputEventScreenDrag d => _fingers.Move(d.Index, ToCore(d.Position)),
            _ => false,
        };
        if (mine) GetViewport().SetInputAsHandled();
    }

    public override void _Process(double delta)
    {
        _playing += delta;
        float alpha = Fade.Alpha(_playing);
        if (alpha != _alpha) { _alpha = alpha; QueueRedraw(); }
    }

    public override void _Draw()
    {
        var colour = ArtColour with { A = ArtColour.A * Mathf.Max(_alpha, 0) };
        foreach (var pad in Layout.Pads) DrawCircle(new Vector2(pad.Centre.X, pad.Centre.Y), pad.ArtRadius, colour);
    }

    static void Press(string action) => Input.ActionPress(action);
    static void Release(string action) => Input.ActionRelease(action);
    static float Sq(float x) => x * x;
    static System.Numerics.Vector2 ToCore(Vector2 v) => new(v.X, v.Y);
}
