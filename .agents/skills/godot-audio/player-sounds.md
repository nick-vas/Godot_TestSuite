# Sounds for the player's own actions

A sound designer's rules from a GDC talk on game feel (Joonas Turner; `${CLAUDE_PLUGIN_ROOT}/docs/gdc/game-feel-with-sound.md`).
They are his practice, not a standard: if a longer or slower sound feels better in play, keep it.

- **Start on the hit.** A build-up before the hit makes a press feel like it moved a character; an instant start makes it
  feel like the player did it. A slow start is a tool for weight (an over-encumbered jump), not a default. Trim leading
  silence and fades from the file, and play it on the frame of the input (`godot-juice`).
- **Short first.** A long jump or door sound tires the player within a few repeats. Start short; keep a longer take only
  when it plays better.
- **One impact layer per game.** A tiny transient (he uses 5 to 20 ms) at the very start of every action sound. Its level
  sets each sound's punch, and it can carry the low end, so the body stays lean and twenty shotguns at once stay tight
  instead of muddy. Enemies may get a different one.
- **Layers that belong together.** Record each family (actions, voices, enemies) with one fixed microphone and preamp,
  and run every finished sound through one master chain (the same limiter and saturation). Godot imports files with no
  DAW master bus in between: put that chain on every export.
- **Duck under the player's actions, slightly.** Not only under dialogue: dip the other buses a little when the player
  fires, jumps or presses UI, more for a rocket launcher than a pistol, optionally with a filter, through the snapshot
  code in SKILL.md section 5. Try this before changing the mix balance.
- **Cut what costs feel.** Any ducking, reverb or occlusion system that adds input lag, or stops feeling good, goes.
- **Cues instead of HUD reads** in action: a shout or a metal clank when the ammo runs out.
- The `audio` command reports each file's `onsetMs` (when it comes within 10 dB of its loudest 10 ms) and warns when a
  `sfx` or `ui` file takes more than 20 ms. The 20 ms is the kit's choice, not the talk's; `-MaxOnsetMs` changes it for a
  game that wants slower attacks. The `juice` runner's `withinMs` ends at `Play()`: the onset comes on top.
