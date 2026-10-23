namespace GlowmossRidge;

using System.Collections.Generic;
using Godot;

/// <summary>
/// The --autoplay player. It runs right, jumps near the end of the ground it stands on, up onto a higher platform ahead,
/// and over (or onto) a beetle ahead, holding jump for the full arc. It never looks at thorns: that blind spot is where
/// it gets hurt, once per patch, which the juice run needs to see.
/// </summary>
public sealed class Bot
{
    /// <summary>Jump when the ground ends this close ahead ...</summary>
    public const float EdgeLead = 0.45f;
    /// <summary>... or a higher platform starts this close ahead, if it is no higher than it can climb ...</summary>
    public const float StepLook = 1.4f;
    public const float ClimbMax = 1.9f;
    /// <summary>... or a beetle is this close ahead.</summary>
    public const float BeetleLook = 2.4f;

    private List<Aabb> _boxes = new();

    public void Setup(List<Aabb> boxes)
    {
        _boxes = boxes;
    }

    /// <summary>The direction (always right), whether jump went down this tick, and whether it is held.</summary>
    public (float Direction, bool JumpPressed, bool JumpHeld) Decide(Vector3 feet, bool onFloor, bool rising, Godot.Collections.Array<Node> beetles)
    {
        bool jump = onFloor && ShouldJump(feet, beetles);
        return (1f, jump, jump || rising);
    }

    private bool ShouldJump(Vector3 feet, Godot.Collections.Array<Node> beetles)
    {
        float groundEnd = GroundEnd(feet);
        if (!float.IsNaN(groundEnd) && groundEnd - feet.X < EdgeLead)
            return true;
        foreach (Aabb box in _boxes)
        {
            float ahead = box.Position.X - feet.X;
            float rise = box.End.Y - feet.Y;
            if (ahead > 0f && ahead < StepLook && rise > 0.3f && rise <= ClimbMax)
                return true;
        }
        foreach (Node node in beetles)
        {
            var beetle = (Node3D)node;
            float ahead = beetle.Position.X - feet.X;
            if (ahead > 0f && ahead < BeetleLook && Mathf.Abs(beetle.Position.Y - feet.Y) < 0.8f)
                return true;
        }
        return false;
    }

    /// <summary>Where the ground under the feet ends on the right, across platforms that touch at the same height; NaN in the air.</summary>
    private float GroundEnd(Vector3 feet)
    {
        float end = float.NaN;
        foreach (Aabb box in _boxes)
        {
            if (Mathf.Abs(box.End.Y - feet.Y) < 0.15f && box.Position.X - Player.HalfWidth <= feet.X && feet.X <= box.End.X + Player.HalfWidth)
                end = float.IsNaN(end) ? box.End.X : Mathf.Max(end, box.End.X);
        }
        if (float.IsNaN(end))
            return end;
        bool grew = true;
        while (grew)
        {
            grew = false;
            foreach (Aabb box in _boxes)
            {
                if (Mathf.Abs(box.End.Y - feet.Y) < 0.15f && box.Position.X <= end + 0.01f && box.End.X > end)
                {
                    end = box.End.X;
                    grew = true;
                }
            }
        }
        return end;
    }
}
