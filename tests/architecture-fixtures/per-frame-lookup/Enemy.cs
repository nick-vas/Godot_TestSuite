using Godot;

public partial class Enemy : Node2D
{
    public override void _Process(double delta)
    {
        var player = GetNode<Node2D>("Player");
        Position = Position.MoveToward(player.Position, (float)delta * 50f);
    }
}
