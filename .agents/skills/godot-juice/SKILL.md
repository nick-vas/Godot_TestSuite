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
| Screen shake | weight; small and short | `Camera2D.Offset` driven by noise, decaying over 0.1 to 0.3 s; scale it by a settings slider |
| Squash and stretch | elasticity on jumps, landings and hits | a `Tween` on the visual's `Scale`, never on the physics body |
| Flash | marks who was hit | a shader `flash` uniform on the visual for 1 to 3 frames |
| Particles | spark, dust, debris at the contact point | pre-warmed `GpuParticles2D`, one-shot, pooled (`godot-patterns` Object Pool) |
| Telegraphs | a danger is readable before it lands | a wind-up animation or marker at least 300 ms ahead |
| Numbers | damage and score pop where they happened | pooled labels with a short rise-and-fade tween |

Keep feedback on the presentation side: it must never change gameplay state, so tests and bots stay deterministic
(`godot-architecture`).

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
