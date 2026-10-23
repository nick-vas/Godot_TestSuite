namespace OrbitPatrol;

using System;

/// <summary>Points and the combo multiplier. Free of Godot types, so its tests run without the engine.</summary>
public sealed class Score
{
    /// <summary>Raised whenever the points change, so whoever shows them never has to ask.</summary>
    public event Action? Changed;

    public int Points { get; private set; }
    public int Combo { get; private set; }
    public int Best { get; set; }

    /// <summary>A destroyed enemy worth <paramref name="value"/>: every fifth hit in a row raises the multiplier by one.</summary>
    public int Hit(int value)
    {
        Combo += 1;
        int gained = value * (1 + Combo / 5);
        Points += gained;
        Best = Math.Max(Best, Points);
        Changed?.Invoke();
        return gained;
    }

    /// <summary>A shot left the screen, or the ship was hit: the combo starts again.</summary>
    public void Miss()
    {
        Combo = 0;
    }

    /// <summary>A new game.</summary>
    public void Reset()
    {
        Points = 0;
        Combo = 0;
        Best = 0;
        Changed?.Invoke();
    }
}
