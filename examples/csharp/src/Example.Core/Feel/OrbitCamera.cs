using System;
using System.Linq;
using System.Numerics;

namespace Example.Core.Feel;

/// <summary>Distance and vertical field of view (degrees) wanted at one pitch (radians, positive looks up).</summary>
public readonly record struct PitchFrame(float Pitch, float Distance, float FovDegrees);

/// <summary>
/// Distance and field of view as one function of pitch, so they move together like gears (John Nesky, "50 Game Camera
/// Mistakes", GDC): closer and wider when looking up from a worm's-eye view, a little farther when looking down.
/// Between two frames the camera's distance and the height of the picture at the avatar's depth are interpolated, and
/// the field of view is derived from them. The avatar's size on screen is its height over that picture height, so it
/// only ever grows or only shrinks between two frames. Interpolating distance and field of view each on its own, even
/// between the same frames, can make the avatar grow and then shrink while the player only tilts the camera.
/// </summary>
public sealed class PitchRig
{
    readonly PitchFrame[] _frames;

    public PitchRig(params PitchFrame[] frames)
    {
        if (frames.Length == 0) throw new ArgumentException("A pitch rig needs at least one frame.", nameof(frames));
        foreach (var f in frames)
        {
            if (!(f.Distance > 0) || !(f.FovDegrees > 0 && f.FovDegrees < 180) || !float.IsFinite(f.Pitch))
                throw new ArgumentException($"Frame at pitch {f.Pitch}: distance must be above 0 and the field of view between 0 and 180 degrees.", nameof(frames));
        }
        _frames = frames.OrderBy(f => f.Pitch).ToArray();
    }

    /// <summary>The height of the picture at <paramref name="distance"/> from a camera with this vertical field of view.</summary>
    public static float PictureHeight(float distance, float fovDegrees) => 2f * distance * MathF.Tan(fovDegrees * MathF.PI / 360f);

    /// <summary>Base distance and field of view at a pitch; other effects multiply these rather than replace them.</summary>
    public (float Distance, float FovDegrees) At(float pitch)
    {
        if (pitch <= _frames[0].Pitch) return (_frames[0].Distance, _frames[0].FovDegrees);
        for (int i = 1; i < _frames.Length; i++)
        {
            PitchFrame a = _frames[i - 1], b = _frames[i];
            if (pitch > b.Pitch) continue;
            if (pitch == b.Pitch) return (b.Distance, b.FovDegrees);
            float t = (pitch - a.Pitch) / (b.Pitch - a.Pitch);
            float distance = a.Distance + (b.Distance - a.Distance) * t;
            float height = PictureHeight(a.Distance, a.FovDegrees) + (PictureHeight(b.Distance, b.FovDegrees) - PictureHeight(a.Distance, a.FovDegrees)) * t;
            return (distance, 2f * MathF.Atan(height / (2f * distance)) * 180f / MathF.PI);
        }
        return (_frames[^1].Distance, _frames[^1].FovDegrees);
    }
}

/// <summary>Tuning for <see cref="OrbitCamera"/>. Angles in radians, rates per second of game time.</summary>
public sealed record OrbitSettings
{
    /// <summary>Turn speed at full stick deflection.</summary>
    public float YawSpeed { get; init; } = 2.5f;
    public float PitchSpeed { get; init; } = 1.5f;
    /// <summary>Pitch limits; never straight up or down, where yaw and pitch lose their meaning.</summary>
    public float MinPitch { get; init; } = -1.2f;
    public float MaxPitch { get; init; } = 0.9f;
    /// <summary>How far before each limit the pitch speed starts to fall, so the camera eases into the limit.</summary>
    public float PitchEase { get; init; } = 0.35f;
    /// <summary>How fast the camera swings away from an obstacle its side rays (whiskers) found, at full strength.</summary>
    public float AvoidSpeed { get; init; } = 1.5f;
    /// <summary>When the player turns toward that obstacle: the share of the distance given up at full strength, and how fast.</summary>
    public float SqueezeDepth { get; init; } = 0.5f;
    public float SqueezeRate { get; init; } = 4f;
    /// <summary>After the player last moved the camera, hints and auto-follow wait this long, then fade in over HintFade.</summary>
    public float HintDelay { get; init; } = 1.5f;
    public float HintFade { get; init; } = 1f;
    public float HintRate { get; init; } = 2f;
    /// <summary>Turning to look where the avatar is going: the rate, and the speed below which the camera leaves yaw alone.</summary>
    public float FollowRate { get; init; } = 1f;
    public float MinFollowSpeed { get; init; } = 0.5f;
    /// <summary>The pivot trails the avatar for smoothness, but never by more than MaxLag horizontally or MaxVerticalLag vertically.</summary>
    public float PivotRate { get; init; } = 8f;
    public float MaxLag { get; init; } = 1f;
    public float VerticalRate { get; init; } = 4f;
    public float MaxVerticalLag { get; init; } = 2f;
}

/// <summary>What the game measured this frame. The camera does its own math; the rays are the game's.</summary>
/// <param name="Look">Look stick after <c>StickSettings.Apply</c> (x right, y down as Godot's <c>GetVector</c> reports it).</param>
/// <param name="Avatar">Where the camera's attention point is: the avatar's position plus a head-height offset.</param>
/// <param name="Velocity">The avatar's actual velocity, not the move stick: running into a wall gives zero.</param>
/// <param name="Grounded">On the floor this frame; the camera holds its height through jumps and follows on landing.</param>
/// <param name="Avoid">-1 to 1 from the side rays: the yaw direction (positive raises yaw) that swings away from an obstacle about to block the view.</param>
/// <param name="BehindClearance">Free distance behind the pivot along the view (a ray just behind the camera); infinite when clear.</param>
/// <param name="HintYaw">The yaw that frames a designer's hint target (a distant one: rotate to it), or null.</param>
public readonly record struct OrbitInput(
    Vector2 Look, Vector3 Avatar, Vector3 Velocity, bool Grounded,
    float Avoid = 0f, float BehindClearance = float.PositiveInfinity, float? HintYaw = null);

/// <summary>Where to put the camera: in Godot, <c>GlobalPosition = Position</c>, <c>Rotation = new(Pitch, Yaw, 0)</c>, <c>Fov = FovDegrees</c>.</summary>
public readonly record struct OrbitPose(Vector3 Position, Vector3 Forward, float Yaw, float Pitch, float Distance, float FovDegrees);

/// <summary>
/// A third-person camera kept as yaw, pitch and distance around a pivot that follows the avatar ("50 Game Camera
/// Mistakes", John Nesky, GDC). The world position is derived every frame, so the camera always orbits the avatar and
/// never pivots in place. Each degree of freedom has its own short priority list instead of competing forces that can
/// cancel out: on yaw, the player's turn beats obstacle avoidance, which beats hints and auto-follow; a player turning
/// toward an obstacle moves the camera closer instead of being fought. Rays, sphere checks and level tags are the game's.
/// Axes follow Godot: yaw 0 looks along -Z and positive yaw turns left; positive pitch looks up.
/// </summary>
public sealed class OrbitCamera
{
    readonly PitchRig _rig;
    float _groundHeight, _squeeze = 1f, _behind = float.PositiveInfinity;

    public OrbitCamera(PitchRig rig, OrbitSettings? settings = null)
    {
        _rig = rig;
        Settings = settings ?? new OrbitSettings();
    }

    public OrbitSettings Settings { get; }
    public float Yaw { get; private set; }
    public float Pitch { get; private set; }
    public Vector3 Pivot { get; private set; }
    /// <summary>Seconds since the player last moved the camera; hints and auto-follow wait on it.</summary>
    public float SinceLook { get; private set; } = float.PositiveInfinity;

    /// <summary>Place the camera without easing (level start, respawn, after a cut).</summary>
    public void Reset(Vector3 avatar, float yaw, float pitch)
    {
        Pivot = avatar;
        _groundHeight = avatar.Y;
        Yaw = WrapAngle(yaw);
        Pitch = Math.Clamp(pitch, Settings.MinPitch, Settings.MaxPitch);
        _squeeze = 1f;
        _behind = float.PositiveInfinity;
        SinceLook = float.PositiveInfinity;
    }

    /// <summary>0 while the player is in charge of the camera and for HintDelay after, then rising to 1 over HintFade.</summary>
    public float AutoWeight => Settings.HintFade <= 0f
        ? (SinceLook >= Settings.HintDelay ? 1f : 0f)
        : Math.Clamp((SinceLook - Settings.HintDelay) / Settings.HintFade, 0f, 1f);

    /// <summary>The yaw that looks along a horizontal velocity, or null when slower than <paramref name="minSpeed"/>.</summary>
    public static float? YawAlong(Vector3 velocity, float minSpeed)
    {
        var flat = new Vector2(velocity.X, velocity.Z);
        return flat.Length() < minSpeed || flat == Vector2.Zero ? null : MathF.Atan2(-flat.X, -flat.Y);
    }

    public void Update(in OrbitInput input, float delta)
    {
        var s = Settings;
        FollowPivot(input.Avatar, input.Grounded, delta);

        // Stick right turns right (yaw down); stick up (negative y) looks up. Inversion is StickSettings' job.
        float yawRate = -input.Look.X * s.YawSpeed, pitchRate = -input.Look.Y * s.PitchSpeed;
        SinceLook = input.Look != Vector2.Zero ? 0f : SinceLook + delta;

        // Yaw: one winner per frame.
        bool fighting = false;
        if (yawRate != 0f)
        {
            Yaw += yawRate * delta;
            fighting = input.Avoid != 0f && MathF.Sign(yawRate) == -MathF.Sign(input.Avoid);
        }
        else if (input.Avoid != 0f) Yaw += Math.Clamp(input.Avoid, -1f, 1f) * s.AvoidSpeed * delta;
        else if (AutoWeight > 0f)
        {
            if (input.HintYaw is float hint) Yaw = DampAngle(Yaw, hint, s.HintRate * AutoWeight, delta);
            else if (YawAlong(input.Velocity, s.MinFollowSpeed) is float along) Yaw = DampAngle(Yaw, along, s.FollowRate * AutoWeight, delta);
        }
        Yaw = WrapAngle(Yaw);

        Pitch = EasePitch(Pitch, pitchRate, delta);

        // Distance: squeeze in gradually past an obstacle the player turns toward; an obstacle behind pulls in, never swings.
        float squeezeTarget = fighting ? 1f - s.SqueezeDepth * Math.Min(1f, MathF.Abs(input.Avoid)) : 1f;
        _squeeze = Damp(_squeeze, squeezeTarget, s.SqueezeRate, delta);
        _behind = MathF.Max(0f, input.BehindClearance);
    }

    public OrbitPose Pose
    {
        get
        {
            var (baseDistance, fov) = _rig.At(Pitch);
            float distance = MathF.Min(baseDistance * _squeeze, _behind);
            var forward = new Vector3(-MathF.Sin(Yaw) * MathF.Cos(Pitch), MathF.Sin(Pitch), -MathF.Cos(Yaw) * MathF.Cos(Pitch));
            return new OrbitPose(Pivot - forward * distance, forward, Yaw, Pitch, distance, fov);
        }
    }

    /// <summary>
    /// Moves pitch at <paramref name="rate"/> and slows it inside PitchEase of the limit it is heading for: the speed is
    /// proportional to what is left, so the camera glides into the limit instead of stopping dead. The exact solution, so
    /// the result is the same at any frame rate and never passes the limit. Moving away from a limit is full speed.
    /// </summary>
    public float EasePitch(float pitch, float rate, float delta)
    {
        var s = Settings;
        pitch = Math.Clamp(pitch, s.MinPitch, s.MaxPitch);
        if (rate == 0f || delta <= 0f) return pitch;
        float limit = rate > 0f ? s.MaxPitch : s.MinPitch, speed = MathF.Abs(rate), zone = s.PitchEase;
        float left = MathF.Abs(limit - pitch);
        if (zone <= 0f) left = MathF.Max(0f, left - speed * delta);
        else
        {
            if (left > zone)
            {
                float toZone = (left - zone) / speed;
                if (delta <= toZone) { left -= speed * delta; delta = 0f; }
                else { left = zone; delta -= toZone; }
            }
            if (delta > 0f) left *= MathF.Exp(-speed * delta / zone);
        }
        return rate > 0f ? limit - left : limit + left;
    }

    void FollowPivot(Vector3 avatar, bool grounded, float delta)
    {
        var s = Settings;
        // Horizontal: smooth, on an elastic band with a hard limit so the avatar cannot run off screen.
        var flat = Damp(new Vector2(Pivot.X, Pivot.Z), new Vector2(avatar.X, avatar.Z), s.PivotRate, delta);
        var lag = new Vector2(avatar.X, avatar.Z) - flat;
        if (lag.Length() > s.MaxLag) flat = new Vector2(avatar.X, avatar.Z) - Vector2.Normalize(lag) * s.MaxLag;

        // Vertical: hold the height of the last floor through a jump; follow once landed, or when the avatar leaves the band.
        if (grounded) _groundHeight = avatar.Y;
        float y = Damp(Pivot.Y, _groundHeight, s.VerticalRate, delta);
        y = Math.Clamp(y, avatar.Y - s.MaxVerticalLag, avatar.Y + s.MaxVerticalLag);
        Pivot = new Vector3(flat.X, y, flat.Y);
    }

    /// <summary>Toward a target angle the short way round (170 to -170 degrees is 20 degrees, not 340).</summary>
    public static float DampAngle(float current, float target, float rate, float delta) =>
        current + WrapAngle(target - current) * Weight(rate, delta);

    /// <summary>An angle in -pi to pi.</summary>
    public static float WrapAngle(float angle)
    {
        float wrapped = MathF.IEEERemainder(angle, MathF.Tau);
        return wrapped <= -MathF.PI ? wrapped + MathF.Tau : wrapped;
    }

    // As Smoothing in CameraShake.cs, repeated so this file can be copied into a game on its own.
    static float Weight(float rate, float delta) => 1f - MathF.Exp(-rate * delta);
    static float Damp(float current, float target, float rate, float delta) => current + (target - current) * Weight(rate, delta);
    static Vector2 Damp(Vector2 current, Vector2 target, float rate, float delta) => Vector2.Lerp(current, target, Weight(rate, delta));
}
