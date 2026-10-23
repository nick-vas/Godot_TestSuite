namespace Example.Controls;

using System;
using System.Collections.Generic;
using Example.Core.Controls;
using Example.Core.Ui;
using Godot;

/// <summary>
/// Up and down through a column of controls (the focusable children of this node's parent, in order), so a player who
/// cannot see the list still knows where they are: a step sound on every move and, when the menu loops, a different
/// sound and a rumble on the wrap. Without <see cref="Loop"/> focus stops at the ends. Items never come and go: one
/// that is not available stays in its place, disabled, so a memorised count of presses always reaches the same item.
/// Grids do not loop (XAG 112); use this only for lists.
/// </summary>
public partial class LinearMenu : Node
{
    static readonly StringName Up = "ui_up", Down = "ui_down";
    readonly List<Control> _items = new();

    public bool Loop { get; set; } = true;
    /// <summary>Played on every move: the "click, click, click" that counts the items.</summary>
    public AudioStreamPlayer? StepSound { get; set; }
    /// <summary>Played instead of the step sound when focus wraps; make it plainly different.</summary>
    public AudioStreamPlayer? WrapSound { get; set; }
    public Haptics? Haptics { get; set; }
    /// <summary>Where the wrap rumble goes: the pad the player used last.</summary>
    public InputDevices? Devices { get; set; }

    /// <summary>Focus wrapped; the argument is the item that has it now.</summary>
    public event Action<Control>? Wrapped;

    public override void _Ready()
    {
        foreach (var child in GetParent().GetChildren())
        {
            if (child is not Control { FocusMode: not Control.FocusModeEnum.None } item) continue;
            _items.Add(item);
            item.GuiInput += e => OnItemInput(item, e);
        }
    }

    void OnItemInput(Control item, InputEvent e)
    {
        int delta = e.IsActionPressed(Down, allowEcho: true) ? 1 : e.IsActionPressed(Up, allowEcho: true) ? -1 : 0;
        if (delta == 0) return;
        int index = _items.IndexOf(item);
        if (index < 0) return;
        item.AcceptEvent();   // Godot's own focus move would loop silently, or not at all
        var (to, move) = MenuCursor.Step(index, _items.Count, delta, Loop);
        if (move == MenuMove.Stopped) return;
        _items[to].GrabFocus();
        if (move == MenuMove.Wrapped)
        {
            WrapSound?.Play();
            Haptics?.Play(HapticPatterns.MenuWrap, Devices?.LastJoypad ?? -1);
            Wrapped?.Invoke(_items[to]);
        }
        else StepSound?.Play();
    }
}
