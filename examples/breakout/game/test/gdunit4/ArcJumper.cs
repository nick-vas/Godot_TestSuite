namespace Breakout.Tests;

using System.Collections.Generic;
using Breakout.Core.Platformer;
using Godot;

// The CharacterBody2D wiring the godot-math skill shows under "Jumps designed by height and distance", as a test
// fixture (Breakout has no platformer). It runs sideways at its foot speed, jumps on its first tick on the floor and
// logs its position and floor contact after every physics tick. Exact = false is the usual template: gravity added to
// the velocity before MoveAndSlide, skipped while on the floor.
public partial class ArcJumper : CharacterBody2D
{
    public JumpArc Arc;
    public JumpGravity Gravity;
    public float FootSpeed;
    public bool Exact = true;

    bool _jumped;

    public readonly List<(Vector2 Position, bool Jumped, bool OnFloor)> Log = new();

    public override void _PhysicsProcess(double delta)
    {
        float dt = (float)delta;
        bool onFloor = IsOnFloor();
        bool jumped = onFloor && !_jumped;
        _jumped |= jumped;
        var v = Velocity;
        v.X = FootSpeed;                                         // its own component: the jump never touches it

        if (!Exact)
        {
            if (!onFloor) v.Y += (float)Gravity.For(v.Y < 0, false) * dt;
            if (jumped) v.Y = -(float)Arc.LaunchSpeed;
            Velocity = v;
            MoveAndSlide();
        }
        else if (onFloor && !jumped)
        {
            Velocity = v;
            MoveAndSlide();
        }
        else
        {
            if (jumped) v.Y = -(float)Arc.LaunchSpeed;
            float vy = v.Y;
            var through = new Vector2(v.X, Gravity.Advance(ref vy, false, dt) / dt);   // the average velocity this tick
            v.Y = vy;
            Velocity = through;
            MoveAndSlide();
            Velocity = v + (Velocity - through);                 // the end velocity, minus what a collision took
        }
        Log.Add((Position, jumped, IsOnFloor()));
    }
}
