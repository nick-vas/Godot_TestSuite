# Capturing Great Footage for Game Trailers

- Talk: "Capturing Great Footage for Game Trailers", GDC.
- Speaker: Derek Lieu, trailer editor (Whisper writes "Derek Liu"; the talk's own credits are Firewatch, Dead Cells,
  Subnautica, Tacoma, Ooblets and others).
- Year: not stated. Probably 2018 (inferred, not checked): he is still cutting The Adventure Pals, Ooblets is
  unreleased, a GIF maker he follows is busy with Monster Hunter, and he dates the Mad Max game to 2015.
- Video: https://www.youtube.com/watch?v=nVeihUFtEkg

Names that are probably mistranscribed: "Kurt Gartner" (a fellow trailer maker), "Scott Goodrow" (The Wild Eternal),
"AtSoonHeLegend" (a GIF account), "Octageddon" and "Wajidai's Unavowed" (Wadjet Eye's Unavowed).

## What the talk teaches

1. **Footage reaches more people than the game.** Released capture is the only time the developer controls how the game
   looks; good capture communicates, so a shot nobody can read is a failed shot.
2. **Four factors set how hard a game is to capture**: visual feedback, camera distance, number of objects on screen and
   the audience's familiarity. Far cameras with many objects need a way to create focus.
3. **Capture is filmmaking, not playing**: the capture artist directs, operates the camera and puppets the character.
   Composition (centre or rule of thirds, eye trace across cuts), readability ("Squint at your shots to check their
   readability"; one idea per shot, remove extra enemies, zoom in) and performance (how the character moves is
   character).
4. **Debug tools for capture, the essentials**: switch off the HUD, on-screen text and especially button prompts (with
   them a cross-platform game is captured once per platform); a music toggle, because music mixed into the capture makes
   its sound effects unusable; level skip, teleport with a position display, a level number on screen, item and enemy
   spawning, invincibility, a fast mode, a "tourist mode" past enemies, cursor and object-highlight toggles, time of day.
5. **A free camera, tuned for smooth movement** rather than precision: adjustable speed by hotkeys or sliders, not
   console values; dead zones; input smoothing (averaged over time); a stick curve gentle near the centre; up and down
   on the triggers. First person adds a head-bob toggle; third person a camera that follows the player at an offset,
   can be detached, and a player-visibility toggle. A second controller as the camera helps (Mad Max's video mode).
6. **Time**: a button that freezes the action while the camera moves, for new angles and match cuts. Slow motion helps
   perform a sequence but misrepresents a game without it; "If adding options for multiple time scales, just whole
   numbers are better", so the editor can restore normal speed exactly.
7. Also: VR capture tips, practice games, capture hardware and software, and (in Q&A) trailers of 90 seconds or less.

## What the kit took

- `.agents/skills/godot-debug-tools/SKILL.md`, section 7 "Capture mode": a debug-only `--capture=` flag
  (`nohud`, `nomusic`, `nocursor`, `freeze`, `timescale=N` or `1/N`, whole numbers only) in a C# autoload, F6 and F7 to
  toggle the HUD and the freeze at run time, the free-camera requirements and a C# `FreeCamera` (smoothing, dead zone
  from the Input Map, a stick curve, speeds on keys 1 to 5, triggers for height, real time while frozen or scaled).
- `.agents/skills/godot-store-page/SKILL.md`: the trailer bullet points to it; store screenshots keep the UI.
- `tests/capture-fixture` (the skill's two C# files verbatim, a HUD layer and a world-space prompt in group `hud`, Music
  and SFX buses, a probe) and `tests/Test-Capture.ps1`, run in the self-test workflow's `measure` job under Xvfb. It also
  checks that the skill quotes the fixture's files exactly.
- Kit additions, not the talk's: the autoload raises `Engine.PhysicsTicksPerSecond` with the time scale so physics keeps
  its step; unknown modes fail the run (`engine-errors`), which catches typos.

## Measured (`pwsh tests/Test-Capture.ps1`, Godot 4.7.2 mono, Xvfb, 640x360)

| Case | Result |
|---|---|
| `shot -GameArgs '--capture=nohud+nomusic+nocursor' -Baseline <normal>` | 25.66% of the picture changed (the HUD bar is the top 25%); the box and world text did not |
| Same run, `AudioServer` | Music muted, SFX and Master not; cursor hidden; the game still runs |
| `--capture=freeze+timescale=2`, free camera flying | player moved 0, camera moved; time scale 2, physics ticks 120; F7 resumes |
| `delta` of an always-processing node while frozen at time scale 2 | 1.82 s per real second (1.01 at time scale 1), so the camera divides by `Engine.TimeScale` |
| Fixture without the autoload | 9 of 18 checks fail (0% changed, Music unmuted, not paused, time scale 1) |
| Music muted through Master, or a camera left pausable | the Music-only check, or the camera-moves check, fails |

## Not taken, and doubts

- Composition, readability and performance advice, hardware, editing software and VR tips: editorial craft that no check
  can enforce. The store-page skill's trailer rules cover what a page needs.
- Level skip, teleport, spawning, invincibility and the rest of point 4 are listed as flags for section 2 of the skill,
  not implemented: each depends on the game.
- Head bob, third-person follow and detach, player visibility, a second controller as camera and 2D zoom: described,
  not coded; they depend on the game's own camera and controls.
- Hiding the HUD every frame can let a node shown by a timer or tween callback flash for one frame (those run after
  `_Process`); the skill puts the group on `CanvasLayer`s to avoid it. Not measured.
