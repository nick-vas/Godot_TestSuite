using System.Numerics;

namespace Example.Core.Ai;

/// <summary>
/// True when nothing blocks the segment from <paramref name="from"/> to <paramref name="to"/>. Tests fake occlusion with
/// it; a Godot game wraps <c>PhysicsDirectSpaceState2D.IntersectRay</c> (an empty result means clear). This is the
/// expensive call: <see cref="VisionSensor"/> makes it last and as rarely as it can.
/// </summary>
public delegate bool LineOfSight(Vector2 from, Vector2 to);

/// <summary>
/// The vision shape Eric Martel calls a pie rather than a cone ("Can You See Me Now?", GDC): an angle
/// opening, a far distance and an optional near distance, in top-down 2D. A 3D game adds top and bottom cut-offs.
/// </summary>
/// <param name="HalfAngle">Half the opening, in radians: 0.6 sees about 69 degrees in all.</param>
/// <param name="Near">Points closer than this are outside this shape (0 for none); a second shape can cover them.</param>
public readonly record struct VisionPie(float HalfAngle, float Far, float Near = 0)
{
    /// <summary>Whether <paramref name="point"/> is inside, worked out in the eye's local space; no ray is cast.</summary>
    /// <param name="facing">The direction the eye looks; any length.</param>
    /// <param name="rangeFactor">Scales <see cref="Far"/>; 0 sees nothing.</param>
    public bool Contains(Vector2 eye, Vector2 facing, Vector2 point, float rangeFactor = 1)
    {
        Vector2 local = point - eye;
        float distance = local.Length();
        if (distance > Far * rangeFactor || distance < Near || rangeFactor <= 0) return false;
        if (distance < 1e-6f) return true;
        // Within the half angle when cos(angle to facing) >= cos(half angle); no acos needed.
        return Vector2.Dot(local / distance, Vector2.Normalize(facing)) >= MathF.Cos(HalfAngle);
    }
}

/// <summary>
/// The effects that change what an agent sees (fog, a storm, a flashbang, a designer's "this guard is blind"), kept as
/// a stack rather than one flag: each effect pushes its own entry and pops only that entry, so a flashbang wearing off
/// leaves the designer's blind in place. Entries can only reduce sight; a factor above 1 counts as 1, because players
/// learn the ranges and a modifier that extends them breaks what they learned.
/// </summary>
public sealed class VisionModifiers
{
    readonly List<(int Handle, string Name, float Factor)> _active = new();
    int _next;

    /// <param name="rangeFactor">0 blinds, 0.5 halves the far distance; values above 1 are treated as 1.</param>
    /// <returns>The handle to pass to <see cref="Pop"/>.</returns>
    public int Push(string name, float rangeFactor)
    {
        _active.Add((++_next, name, Math.Clamp(rangeFactor, 0, 1)));
        return _next;
    }

    /// <summary>Removes the entry <paramref name="handle"/> names, wherever it is in the stack. False if already gone.</summary>
    public bool Pop(int handle) => _active.RemoveAll(m => m.Handle == handle) > 0;

    /// <summary>The product of every active factor: 1 with none.</summary>
    public float RangeFactor => _active.Aggregate(1f, (product, m) => product * m.Factor);

    /// <summary>The active effects' names, oldest first: for a debug display, and for the animation that shows the player why.</summary>
    public IEnumerable<string> Active => _active.Select(m => m.Name);
}

/// <summary>
/// One agent's eyes: a <see cref="VisionPie"/> and its <see cref="VisionModifiers"/>. Vision is on or off, and runs
/// cheapest first: the caller filters which entities to try, the shape and range reject what is outside, and only then
/// is a ray cast, one sample point at a time, stopping at the first clear one.
/// </summary>
public sealed class VisionSensor
{
    public VisionSensor(VisionPie pie) => Pie = pie;

    public VisionPie Pie { get; set; }
    public VisionModifiers Modifiers { get; } = new();

    /// <summary>The far distance after modifiers.</summary>
    public float Range => Pie.Far * Modifiers.RangeFactor;

    /// <summary>
    /// Whether any of <paramref name="samples"/> (points on the target: head, hips, hands) is inside the shape and has a
    /// clear line from <paramref name="eye"/>. A twig in front of one point does not hide a target whose other points
    /// show. Samples outside the shape cost no ray.
    /// </summary>
    /// <param name="eye">Where the agent sees from. Once its weapon is out, pass the muzzle, so sight and fire agree.</param>
    public bool CanSee(Vector2 eye, Vector2 facing, IReadOnlyList<Vector2> samples, LineOfSight lineOfSight)
    {
        float factor = Modifiers.RangeFactor;
        if (factor <= 0) return false;
        foreach (var point in samples)
            if (Pie.Contains(eye, facing, point, factor) && lineOfSight(eye, point)) return true;
        return false;
    }
}

/// <summary>
/// What an agent remembers of one target between sightings (Daniel Brewer, "Knowledge is Power", GDC): whether
/// it is visible now, where it was last seen and how long ago. Decisions read this, not the world, so a target that
/// slips behind a pillar for a moment is still being chased, and one that sneaks away is searched for where it was.
/// </summary>
public sealed class TargetMemory
{
    public bool Visible { get; private set; }
    public Vector2? LastKnownPosition { get; private set; }
    public float TimeSinceSeen { get; private set; } = float.PositiveInfinity;

    /// <summary>Call once per perception update with this update's result; the position is read only when seen.</summary>
    public void Update(bool seen, Vector2 targetPosition, float delta)
    {
        Visible = seen;
        if (seen)
        {
            LastKnownPosition = targetPosition;
            TimeSinceSeen = 0;
        }
        else TimeSinceSeen += delta;
    }

    /// <summary>Still treated as a known target: seen within the last <paramref name="graceSeconds"/>.</summary>
    public bool IsTracked(float graceSeconds) => LastKnownPosition.HasValue && TimeSinceSeen <= graceSeconds;
}
