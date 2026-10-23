namespace GlowmossRidge;

using Godot;

/// <summary>A puff kicked up by the climber's feet; the game ages it, grows it and frees it.</summary>
public partial class Dust : MeshInstance3D
{
    public float Age { get; set; }
}
