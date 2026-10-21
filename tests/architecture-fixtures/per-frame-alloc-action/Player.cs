using Godot;

public partial class Player : Node2D
{
    public override void _PhysicsProcess(double delta)
    {
        Position += new Vector2(Input.GetAxis("move_left", "move_right"), 0);
    }
}
