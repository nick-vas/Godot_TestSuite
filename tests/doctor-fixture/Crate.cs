using Godot;

// Pushed by a force each physics tick: the same judder as player.gd, in C#.
public partial class Crate : RigidBody3D
{
    [Export] public Vector3 Push { get; set; } = new(0, 0, 2);

    public override void _PhysicsProcess(double delta)
    {
        ApplyCentralForce(Push);
    }
}
