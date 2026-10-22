---
name: godot-juice
description: Use when a Godot game feels flat or unresponsive, when adding feedback to hits, jumps, pickups or deaths, or when checking that every action gets feedback in time.
---

# Juice: feedback a player can feel, checked by a bot

"Juice" is the feedback that makes an action land: the game answers within a tenth of a second, through more than one sense.
Add it deliberately, and verify it with the `juice` runner instead of by eye.

## Checklist

| Feedback | What it does | Godot 4 |
|---|---|---|
| Response under 100 ms | the action visibly starts on the frame it is pressed | act in `_UnhandledInput`/`_PhysicsProcess` of that frame, never after an await |
| Sound on every action | confirms the action without looking | `AudioStreamPlayer` with a few variations and slight `PitchScale` randomness |
| Hit-stop | a 30 to 80 ms freeze on a big hit sells the impact | pause the two actors (`ProcessMode`), not `Engine.TimeScale`, which also slows UI and audio |
| Screen shake | weight; small and short | trauma squared on smooth noise, added to a camera the shake never moves; rotation only in 3D (see Screen shake); scale it by a 0 to 100% settings slider (XAG 117) |
| Squash and stretch | elasticity on jumps, landings and hits | a `Tween` on the visual's `Scale`, never on the physics body |
| Button press bounce | the button answers the finger | scale a child visual (a `TextureRect` or `Panel` with `MouseFilter = Ignore`), never the `Button`: Godot hit-tests a `Control` through its transform, so at 0.8 a click 5 px inside the corner missed (tested, 4.7.2). Touch builds need no hover look |
| Flash | marks who was hit | a shader `flash` uniform on the visual for 1 to 3 frames; never more than three flashes a second over about 20% of the screen, less for saturated red (WCAG 2.3.1, XAG 118: a seizure risk): at a fast hit rate, flash only the first hit or tint instead |
| Particles | spark, dust, debris at the contact point | pre-warmed `GpuParticles2D`, one-shot, pooled (`godot-patterns` Object Pool) |
| Telegraphs | a danger is readable before it lands | a wind-up animation or marker at least 300 ms ahead |
| Numbers | damage and score pop where they happened | pooled labels with a short rise-and-fade tween |
| Marks | a death or big hit leaves a trace: where it happened, and by fading, when (Move or Die's death paint, GDC) | a `Sprite2D` splat in the victim's colour, randomly rotated and scaled, drawn behind the play layer (`ZIndex`), its `Modulate` alpha tweened down over seconds; pooled, with a cap |
| Rumble | the player who did not see it still feels it | `godot-input` haptics: one helper scaled by the player's setting, never the only cue |

Feedback is information, not decoration. Nicolae Berbece layered Move or Die's death (sounds, paint, particles, shake,
a colour split, a shockwave, rumble) until players knew someone had died elsewhere on screen without looking there.
In the `juice` runner, `mark` and `rumble` are feedback names like any other.

Optional, at boot: a short sound under the splash logo tells the player the game is running; Kenji Eno had Ryuichi
Sakamoto write the Dreamcast's (*Untold History*). Keep the splash short and skippable.

Keep feedback on the presentation side: it must never change gameplay state, so tests and bots stay deterministic
(`godot-architecture`).

## Screen shake

From the GDC talk "Juicing Your Cameras With Math":

- Keep **trauma** (0 to 1) separate from the shake. Each hit adds to it (about 0.5 for a heavy one, 0.1 to 0.2 for a light
  one, clamped at 1) and it falls **linearly** in game time. Shake = trauma squared (or cubed): heavy and light hits feel
  clearly different, three light hits in a row escalate, and the shake fades out instead of stopping dead.
- Drive each channel with **smooth noise** sampled at game time (`FastNoiseLite`, a different row or seed per channel, or x
  moves with y), never a new random value each frame: random values jitter at full speed in slow motion and at every frame
  rate, while sampled noise slows with `Engine.TimeScale`, repeats with its seed, and at 1 to 2 cycles a second becomes a
  handheld-camera sway.
- **2D**: translation plus a little rotation (`IgnoreRotation = false`). **3D**: rotation only (pitch, yaw and roll, each
  with its own maximum): moving a 3D camera throws near geometry around and pushes the camera into walls. **VR**: none.
- Never move the real camera. The follow code owns the camera's position; the shake rebuilds its offset from scratch every
  frame. In 3D, shake a child `Camera3D` of the pivot that follows and aims, and touch only its `Rotation`.

```csharp
public partial class ShakeCamera : Camera2D   // its parent or the follow code moves it; the shake never does
{
    [Export] public float MaxOffset = 12f, MaxAngle = 0.05f, Decay = 1.5f, NoiseSpeed = 20f;
    [Export] public float Strength = 1f;   // the 0 to 100% settings slider
    private readonly FastNoiseLite _noise = new() { Seed = 1, Frequency = 1f };
    private float _trauma, _time;

    public void AddTrauma(float amount) => _trauma = Mathf.Clamp(_trauma + amount, 0f, 1f);

    public override void _Process(double delta)
    {
        _trauma = Mathf.Max(_trauma - Decay * (float)delta, 0f);
        _time += (float)delta * NoiseSpeed;   // delta is game time: slow motion slows the shake too
        float shake = _trauma * _trauma * Strength;
        Offset = new Vector2(_noise.GetNoise2D(_time, 0f), _noise.GetNoise2D(_time, 50f)) * MaxOffset * shake;
        Rotation = _noise.GetNoise2D(_time, 100f) * MaxAngle * shake;
    }
}
```

In 3D the child camera gets `Rotation = new Vector3(pitch, yaw, roll) * shake` from three noise rows, and its `Position`
stays where the pivot put it. A tested trauma and noise core:
`${CLAUDE_PLUGIN_ROOT}/examples/breakout/src/Breakout.Core/Feel/CameraShake.cs`. Smoothing a follow camera: `godot-math`.

## Make it checkable

1. Log one line per gameplay event and per feedback, with game time in milliseconds:
   `[juice] event brick_hit 1234.5` and `[juice] feedback flash 1240.1`. Game time is the sum of `_Process` deltas, kept by an
   autoload, so it is the same on every machine:

   ```csharp
   public partial class Juice : Node   // autoload
   {
       private static double _ms;
       public override void _Process(double delta) => _ms += delta * 1000.0;
       public static void Event(string name) => GD.Print($"[juice] event {name} {_ms:F1}");
       public static void Feedback(string name) => GD.Print($"[juice] feedback {name} {_ms:F1}");
   }
   ```
   (The interpolated strings allocate; that is fine for a log line on an event, not for one every frame.)

2. Write `juice.json` in the Godot project:

   ```json
   { "frames": 1800, "args": ["--autoplay", "--seed=1"],
     "rules": [ { "event": "brick_hit", "feedback": ["flash", "sfx"], "withinMs": 100 },
                { "event": "player_death", "feedback": ["shake", "sfx"], "withinMs": 100 } ] }
   ```

3. The `juice` runner is detected from it and runs with every `test`: Godot plays headless at a fixed 60 fps for `frames`
   frames with `args` (your bot, `godot-automation-hooks`), and each rule fails when an event had no such feedback within the
   window, or never happened at all (the bot did not reach it).

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/godot-ci.ps1 test -Json -Quiet -Runners juice
```

How it looks is a different question: screenshots and the style guide are `/look`.
