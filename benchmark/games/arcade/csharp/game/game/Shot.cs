namespace OrbitPatrol;

using Godot;

/// <summary>A shot from the ship (up) or an enemy (down). It moves itself; the game checks what it hits.</summary>
public partial class Shot : Sprite2D
{
    public Vector2 Velocity { get; set; }
    public bool Hostile { get; set; }

    /// <summary>Set once it has hit something, so it hits nothing else before it is removed.</summary>
    public bool Spent { get; set; }
    public Vector2 Size { get; set; } = new(6, 16);

    public override void _PhysicsProcess(double delta)
    {
        Position += Velocity * (float)delta;
    }
}
