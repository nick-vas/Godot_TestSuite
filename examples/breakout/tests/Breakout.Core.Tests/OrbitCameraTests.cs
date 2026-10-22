using System.Numerics;
using Breakout.Core.Feel;
using Xunit;

namespace Breakout.Core.Tests;

// The third-person camera rules from "50 Game Camera Mistakes" (John Nesky, GDC) that can be checked as plain math.
public sealed class OrbitCameraTests
{
    static readonly int[] FrameRates = [30, 60, 144];
    const float Deg = MathF.PI / 180f;

    // Looking down: a little farther. Level: the standard view. Looking up (worm's eye): closer and wider.
    static PitchRig Rig() => new(new PitchFrame(-1f, 7f, 65f), new PitchFrame(0f, 6f, 60f), new PitchFrame(0.7f, 3f, 95f));

    static OrbitCamera Camera(OrbitSettings? settings = null)
    {
        var camera = new OrbitCamera(Rig(), settings);
        camera.Reset(Vector3.Zero, yaw: 0f, pitch: 0f);
        return camera;
    }

    // How big the avatar looks: its height over the height of the picture at its depth.
    static float AvatarSize(float distance, float fovDegrees) => 1f / PitchRig.PictureHeight(distance, fovDegrees);

    static bool Monotonic(IReadOnlyList<float> values)
    {
        bool up = true, down = true;
        for (int i = 1; i < values.Count; i++)
        {
            if (values[i] < values[i - 1] - 1e-6f) up = false;
            if (values[i] > values[i - 1] + 1e-6f) down = false;
        }
        return up || down;
    }

    [Fact]
    public void Tilting_never_makes_the_avatar_grow_and_then_shrink()
    {
        var rig = Rig();
        var sizes = new List<float>();
        for (int i = 0; i <= 200; i++)
        {
            var (distance, fov) = rig.At(i * 0.7f / 200);   // level to worm's eye
            sizes.Add(AvatarSize(distance, fov));
        }
        Assert.True(Monotonic(sizes));

        // The same frames with distance and field of view interpolated each on its own: the avatar first shrinks
        // (the field of view widens faster than the camera closes in), then grows.
        var naive = new List<float>();
        for (int i = 0; i <= 200; i++)
        {
            float t = i / 200f;
            naive.Add(AvatarSize(6f + (3f - 6f) * t, 60f + (95f - 60f) * t));
        }
        Assert.False(Monotonic(naive));
    }

    [Fact]
    public void The_rig_hits_its_frames_and_stays_between_them()
    {
        var rig = Rig();
        Assert.Equal((6f, 60f), (rig.At(0f).Distance, MathF.Round(rig.At(0f).FovDegrees, 4)));
        Assert.Equal(95f, rig.At(0.7f).FovDegrees, 1e-3f);
        Assert.Equal(65f, rig.At(-1f).FovDegrees, 1e-3f);
        Assert.Equal(rig.At(0.7f), rig.At(1.5f));   // held past the last frame
        for (int i = 0; i <= 100; i++)
        {
            var (distance, fov) = rig.At(i * 0.007f);
            Assert.InRange(distance, 3f, 6f);
            Assert.InRange(fov, 60f, 95f);
        }
        Assert.Throws<ArgumentException>(() => new PitchRig(new PitchFrame(0f, 0f, 60f)));
    }

    [Fact]
    public void The_camera_orbits_the_avatar_and_never_pivots_in_place()
    {
        var camera = new OrbitCamera(Rig());
        var avatar = new Vector3(3f, 1f, -2f);
        foreach (float yaw in new[] { 0f, 1f, 2.5f, -2f })
        foreach (float pitch in new[] { -0.9f, 0f, 0.6f })
        {
            camera.Reset(avatar, yaw, pitch);
            var pose = camera.Pose;
            Assert.True(Vector3.Distance(avatar, pose.Position + pose.Forward * pose.Distance) < 1e-4f);   // looks at the avatar
            Assert.Equal(camera.Pose.Distance, Vector3.Distance(avatar, pose.Position), 1e-4f);
        }
        camera.Reset(Vector3.Zero, 0f, 0f);
        Assert.True(Vector3.Distance(new Vector3(0f, 0f, 6f), camera.Pose.Position) < 1e-5f);    // behind, on +Z: Godot looks along -Z
        camera.Reset(Vector3.Zero, MathF.PI / 2, 0f);
        Assert.True(Vector3.Distance(new Vector3(-1f, 0f, 0f), camera.Pose.Forward) < 1e-5f);   // positive yaw turns left
        camera.Reset(Vector3.Zero, 0f, 0.5f);
        Assert.True(camera.Pose.Position.Y < 0f);   // looking up puts the camera low, which is why it must come closer
    }

    [Fact]
    public void Pitch_slows_before_its_limit_instead_of_stopping_dead()
    {
        var after = new List<float>();
        foreach (int fps in FrameRates)
        {
            var camera = Camera();
            float dt = 1f / fps, largestDrop = 0f, previousSpeed = camera.Settings.PitchSpeed;
            for (int frame = 0; frame < 3 * fps; frame++)
            {
                float before = camera.Pitch;
                camera.Update(new OrbitInput(new Vector2(0f, -1f), Vector3.Zero, Vector3.Zero, true), dt);
                float speed = (camera.Pitch - before) / dt;
                largestDrop = MathF.Max(largestDrop, previousSpeed - speed);
                previousSpeed = speed;
                Assert.True(camera.Pitch <= camera.Settings.MaxPitch);
                if (frame == fps / 2 - 1) after.Add(camera.Pitch);
            }
            Assert.InRange(camera.Settings.MaxPitch - camera.Pitch, 0f, 1e-3f);
            // A frame never loses more than a fifth of full speed (an eighth at 60 fps); speed then clamp loses all of it.
            Assert.True(largestDrop < camera.Settings.PitchSpeed * (fps == 30 ? 0.25f : 0.13f), $"{fps} fps: speed fell {largestDrop} in one frame");
        }
        Assert.True(after.Max() - after.Min() < 1e-4f);   // the same pitch after half a second at any frame rate
    }

    [Fact]
    public void Pushing_away_from_a_limit_moves_at_full_speed()
    {
        var camera = new OrbitCamera(Rig());
        camera.Reset(Vector3.Zero, 0f, camera.Settings.MaxPitch);
        camera.Update(new OrbitInput(new Vector2(0f, 1f), Vector3.Zero, Vector3.Zero, true), 0.1f);
        Assert.Equal(camera.Settings.MaxPitch - camera.Settings.PitchSpeed * 0.1f, camera.Pitch, 1e-5f);
    }

    [Fact]
    public void A_hint_waits_after_the_player_looks_then_takes_over()
    {
        var camera = Camera();
        float hint = 1.2f, dt = 1f / 60;
        for (int frame = 0; frame < 30; frame++)
        {
            float before = camera.Yaw;
            camera.Update(new OrbitInput(new Vector2(-0.5f, 0f), Vector3.Zero, Vector3.Zero, true, HintYaw: hint), dt);
            Assert.Equal(before + 0.5f * camera.Settings.YawSpeed * dt, camera.Yaw, 1e-5f);   // the player only
        }
        float released = camera.Yaw;
        for (float t = 0f; t < camera.Settings.HintDelay - dt; t += dt)
        {
            camera.Update(new OrbitInput(Vector2.Zero, Vector3.Zero, Vector3.Zero, true, HintYaw: hint), dt);
            Assert.Equal(released, camera.Yaw);   // the player's view is left alone during the delay
        }
        for (int frame = 0; frame < 5 * 60; frame++)
            camera.Update(new OrbitInput(Vector2.Zero, Vector3.Zero, Vector3.Zero, true, HintYaw: hint), dt);
        Assert.Equal(hint, camera.Yaw, 1e-2f);
    }

    [Fact]
    public void The_players_turn_beats_obstacle_avoidance_and_the_camera_squeezes_in_instead()
    {
        var camera = Camera();
        float dt = 1f / 60, start = camera.Pose.Distance, largestStep = 0f;
        // The whiskers want to swing left (+yaw, Avoid 1); the player turns right, toward the obstacle.
        for (int frame = 0; frame < 60; frame++)
        {
            float yaw = camera.Yaw, distance = camera.Pose.Distance;
            camera.Update(new OrbitInput(new Vector2(0.6f, 0f), Vector3.Zero, Vector3.Zero, true, Avoid: 1f), dt);
            Assert.Equal(yaw - 0.6f * camera.Settings.YawSpeed * dt, camera.Yaw, 1e-5f);   // the player's turn, untouched
            largestStep = MathF.Max(largestStep, distance - camera.Pose.Distance);
        }
        Assert.True(camera.Pose.Distance < start * 0.6f);   // squeezed past the obstacle
        Assert.True(largestStep < start * 0.05f);            // gradually, not a cut
        // Adding the two as forces would have cancelled: 0.6 * 2.5 to the right against 1 * 1.5 to the left.
        Assert.Equal(0f, -0.6f * camera.Settings.YawSpeed + 1f * camera.Settings.AvoidSpeed, 1e-5f);

        // Hands off: the camera swings away from the obstacle by itself, and the distance comes back.
        float swing = camera.Yaw;
        for (int frame = 0; frame < 120; frame++) camera.Update(new OrbitInput(Vector2.Zero, Vector3.Zero, Vector3.Zero, true, Avoid: 1f), dt);
        Assert.Equal(swing + 2f * camera.Settings.AvoidSpeed, camera.Yaw, 1e-3f);
        Assert.Equal(start, camera.Pose.Distance, 1e-2f);
    }

    [Fact]
    public void An_obstacle_behind_pulls_the_camera_in_without_swinging()
    {
        var camera = Camera();
        camera.Update(new OrbitInput(Vector2.Zero, Vector3.Zero, Vector3.Zero, true, BehindClearance: 2f), 1f / 60);
        Assert.Equal(0f, camera.Yaw);
        Assert.Equal(2f, camera.Pose.Distance);
    }

    [Fact]
    public void Auto_follow_turns_toward_where_the_avatar_goes_and_the_short_way_round()
    {
        var camera = Camera();
        for (int frame = 0; frame < 240; frame++) camera.Update(new OrbitInput(Vector2.Zero, Vector3.Zero, Vector3.Zero, true), 1f / 60);
        Assert.Equal(0f, camera.Yaw);   // standing still (or running into a wall): yaw is left alone

        var running = new Vector3(4f, 0f, 0f);   // along +X: the camera ends up looking along +X, yaw -90 degrees
        for (int frame = 0; frame < 600; frame++) camera.Update(new OrbitInput(Vector2.Zero, Vector3.Zero, running, true), 1f / 60);
        Assert.Equal(-MathF.PI / 2, camera.Yaw, 1e-2f);

        Assert.Equal(-170f * Deg, OrbitCamera.WrapAngle(190f * Deg), 1e-5f);
        float step = OrbitCamera.DampAngle(170f * Deg, -170f * Deg, rate: 1f, delta: 0.1f);
        Assert.True(step > 170f * Deg);   // through 180, not back through 0
    }

    [Fact]
    public void A_jump_in_place_leaves_the_camera_height_alone_until_it_lands_higher()
    {
        var camera = Camera();
        float dt = 1f / 60;
        for (int frame = 0; frame <= 60; frame++)   // a 1.25 m hop that lands where it started
        {
            float t = frame * dt;
            camera.Update(new OrbitInput(Vector2.Zero, new Vector3(0f, 5f * t * (1f - t), 0f), Vector3.Zero, frame == 60), dt);
            Assert.Equal(0f, camera.Pivot.Y);
        }
        for (int frame = 0; frame < 120; frame++)   // onto a 1 m ledge
            camera.Update(new OrbitInput(Vector2.Zero, new Vector3(0f, 1f, 0f), Vector3.Zero, true), dt);
        Assert.Equal(1f, camera.Pivot.Y, 1e-2f);
        for (int frame = 0; frame < 60; frame++)    // off a cliff: the camera follows within its band
        {
            var avatar = new Vector3(0f, 1f - 10f * frame * dt, 0f);
            camera.Update(new OrbitInput(Vector2.Zero, avatar, Vector3.Zero, false), dt);
            Assert.True(camera.Pivot.Y - avatar.Y <= camera.Settings.MaxVerticalLag + 1e-4f);
        }
    }

    [Fact]
    public void A_fast_avatar_never_drifts_further_than_the_lag_limit()
    {
        var camera = Camera();
        float dt = 1f / 60, largest = 0f;
        for (int frame = 1; frame <= 120; frame++)   // 20 m/s; smoothing alone would trail by 20 / 8 = 2.5 m
        {
            var avatar = new Vector3(20f * frame * dt, 0f, 0f);
            camera.Update(new OrbitInput(Vector2.Zero, avatar, Vector3.Zero, true), dt);
            largest = MathF.Max(largest, Vector3.Distance(avatar, camera.Pivot));
        }
        Assert.InRange(largest, camera.Settings.MaxLag - 1e-3f, camera.Settings.MaxLag + 1e-4f);
    }
}
