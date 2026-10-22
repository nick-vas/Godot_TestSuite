namespace Breakout.Tests;

using System.Collections.Generic;
using Breakout.Core.Platformer;
using Godot;

// The CharacterBody2D wiring the godot-input skill shows under "Forgiveness", as a test fixture (Breakout has no
// platformer). It logs what it saw on every physics tick, so tests check the windows without depending on frame timing.
public partial class ForgivingJumper : CharacterBody2D
{
    public static readonly StringName Jump = "jump";
    public const float JumpVelocity = 400;

    readonly JumpForgiveness _jump = JumpForgiveness.Levelhead(Engine.PhysicsTicksPerSecond);

    public readonly List<(bool OnFloor, bool Pressed, bool Jumped)> Log = new();

    public override void _PhysicsProcess(double delta)
    {
        bool onFloor = IsOnFloor();                          // what the last MoveAndSlide found
        bool pressed = Input.IsActionJustPressed(Jump);      // true on one physics tick per press
        bool jumped = _jump.Tick(onFloor, pressed);
        var velocity = Velocity;
        if (!onFloor) velocity += GetGravity() * (float)delta;
        if (jumped) velocity.Y = -JumpVelocity;
        Velocity = velocity;
        MoveAndSlide();
        Log.Add((onFloor, pressed, jumped));
    }
}
