---
name: godot-animation
description: Use when a Godot character or object needs animation states, blending, attacks that must not be cut short, root motion, or when an animation feels stiff, floaty or unreadable.
---

# Animation in Godot 4

`AnimationPlayer` holds the clips; `AnimationTree` decides which play and how they blend (both are `AnimationMixer`s). Notes,
tests and sources: `${CLAUDE_PLUGIN_ROOT}/docs/art.md`.

## 1. A state machine with rules

A tree whose root is an `AnimationNodeStateMachine`: Idle, Walk, Run, Jump, Fall, Attack. Each
`AnimationNodeStateMachineTransition` has:

| Property | Use |
|---|---|
| `SwitchMode` | `Immediate`; `Sync` (switch now, keep the play position: walk to run); `AtEnd` (wait for the clip to end) |
| `AdvanceMode` | `Disabled` (never used); `Enabled` (only by `Travel`); `Auto` (taken by itself when its condition holds) |
| `AdvanceCondition` | a bool parameter, `parameters/conditions/<name>`; true only, so "not moving" is its own condition |
| `AdvanceExpression` | an expression on `AdvanceExpressionBaseNode` (point it at the character), e.g. `is_on_floor()` |
| `XfadeTime`, `XfadeCurve` | the blend between the two; 0.1 to 0.2 s for most moves |
| `Priority` | lower wins when several auto transitions are open |

```csharp
var playback = _tree.Get("parameters/playback").As<AnimationNodeStateMachinePlayback>();
_tree.Set("parameters/conditions/moving", Velocity.Length() > 0.1f);
if (attackPressed) playback.Travel("Attack");
```

Interruption rules, tested in 4.7.2:

- `Travel(x)` follows a path over transitions that are not `Disabled`, ignoring conditions; each step keeps its own switch
  mode. So a travel requested mid-attack waits when every edge out of Attack is `AtEnd`.
- With no path, `Travel` jumps straight there, cutting an attack short. Wire every state you travel to.
- `Start(x)` always cuts in at once: for death, stagger, cutscenes, never for ordinary input.
- A cancel window: an `Attack -> Dodge` edge with `Immediate`, `Auto` and a `can_cancel` condition that the attack clip's
  method track switches on and off.
- A new state machine already has `Start` and `End`; connect `Start -> Idle` with `Auto`, or call `Start("Idle")` before the
  first `Travel`.

## 2. Blending

- `AnimationNodeBlendSpace1D` (speed: idle, walk, run) and `AnimationNodeBlendSpace2D` (strafe), set through
  `parameters/<Name>/blend_position`. Name each blend point (`AddBlendPoint(node, pos, -1, "walk")`): 4.7 warns without one.
  `SyncMode = CyclicMutable` keeps footsteps in phase (`Sync` is deprecated in 4.7). `BlendMode = Discrete` for frame-by-frame
  2D sprites.
- In a blend tree: `OneShot` for an upper-body attack or flinch over locomotion
  (`parameters/<Shot>/request` = `(int)AnimationNodeOneShot.OneShotRequest.Fire`), `Transition`, `Blend2`, `TimeScale`.

## 3. Root motion or in place

| | In place (code moves the body) | Root motion (the clip moves it) |
|---|---|---|
| Feet | can slide; match speeds by hand | never slide |
| Control | tune speed, acceleration and turning in code | tied to the clips; re-author to change |
| Attacks, dodges, climbs | distance drifts from the art | exactly the authored distance |
| Online play | simple to predict and reconcile | the server must run the same tree, deterministically |

Use in-place locomotion and root motion only for short committed actions (lunges, dodges, vaults). Unreal's own guidance is
the same: root motion from montages only for networked games. In Godot set `RootMotionTrack` (e.g.
`"Skeleton3D:Root"`), `CallbackModeProcess = Physics`, and apply it in `_PhysicsProcess`:

```csharp
// RootMotionLocal = true on the tree.
Quaternion *= _tree.GetRootMotionRotation();
var velocity = Quaternion * _tree.GetRootMotionPosition() / (float)delta;
velocity.Y = Velocity.Y + (IsOnFloor() ? 0f : GetGravity().Y * (float)delta);   // gravity stays yours
Velocity = velocity;
MoveAndSlide();
```

## 4. The twelve principles, for games

From Thomas and Johnston's *The Illusion of Life*; review a key animation (an attack, a jump) against each.

| Principle | In a game |
|---|---|
| Squash and stretch | jump take-off and landing, hit reactions, a pressed button; keep the volume |
| Anticipation | the wind-up of a heavy attack is the player's dodge window; longer wind-up, bigger hit |
| Staging | boss telegraphs: pose, colour flash, ground marker, camera; effects never hide the silhouette |
| Straight ahead, pose to pose | pose to pose for gameplay clips with exact hit frames; straight ahead for fire and smoke |
| Follow through, overlap | capes, hair, tails, a weapon trail that lingers, a recovery pose after the swing |
| Slow in and slow out | `Tween` easing, `XfadeCurve`, camera moves |
| Arcs | swings, lobs, jumps and head turns follow curves |
| Secondary action | breathing, blinks (a `OneShot`), footstep dust, weapon sway |
| Timing | frame counts for startup, active and recovery; hit-stop of 2 to 6 frames (`godot-juice`) |
| Exaggeration | bigger flashes, knockback and poses than reality, so they read at gameplay zoom |
| Solid drawing | weight and volume; no perfectly mirrored poses |
| Appeal | a distinct silhouette for the player, each enemy and each boss |

The free references are Wikipedia's "Twelve basic principles of animation" and Alan Becker's video series; the book is *The
Animator's Survival Kit*.

## 5. Prove it

- [ ] a test builds or loads the tree and checks every state and transition the GDD names exists
      (`AnimationNodeStateMachine.HasNode`, `HasTransition`), with each edge out of an attack set to `AtEnd`
- [ ] a flow or bot run presses attack then move, and asserts the attack finished (`GetCurrentNode()` in the log)
- [ ] the `juice` runner pairs each hit with its hit-stop and flash (`godot-juice`)
- [ ] screenshots of key poses at gameplay zoom, judged with `look`
