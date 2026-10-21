using System;
using Godot;

public partial class Events : Node
{
    public static Events Instance { get; private set; }
    public event Action<int> ScoreChanged;
    public override void _Ready() => Instance = this;
}

public static class InvariantNumbers
{
    public static float Read(string cell) => float.Parse(cell, System.Globalization.CultureInfo.InvariantCulture);
}
