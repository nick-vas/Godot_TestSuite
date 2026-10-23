# Stop Getting Lost: Make Cognitive Maps, Not Levels

- Speaker: Nick Aweijian as Whisper transcribed it (spelling unchecked against the GDC Vault listing), a game designer
  at thatgamecompany who worked in architecture before games.
- Year: not stated. The talk is pre-recorded ("pause the video now"), which suggests a virtual GDC, 2021 or later.
- Video: https://www.youtube.com/watch?v=Q1Tczf8vxCM

## Lessons

- A cognitive map is the map of a place a player builds in their head (Tolman's 1948 rat experiments named it).
  Getting lost is that map disagreeing with what the player sees, so the cure is a place whose map is easy to build.
- Kevin Lynch (*The Image of the City*) asked residents to draw their neighbourhoods from memory and found five
  elements: paths, landmarks, districts, edges and nodes (Whisper hears "notes").
- **Paths** catch lost players: once a player stands on one, the choice shrinks to left or right. Walking a path one
  way does not mean knowing it the other way; a hiker who turns back is often unsure it is the same trail.
- **Landmarks** are useful only when they stay put (a giant creature walking the map is not one), work better when
  they look different from each side (the Statue of Liberty, not the radially symmetric Eiffel Tower), and must be seen
  again and again: "If a landmark is only referenced one time, it's not really going to be useful".
- **Districts**: squint at the map; the areas you can still tell apart are the districts. Group like with like, by
  look, meaning or mechanics (an area where you jump high, an area where you drive).
- **Edges** (walls, cliffs, level bounds) should be deliberate and crisp: a blurred edge gives a blurred mental map.
- **Nodes** (hubs, junctions) are where paths meet. Make them places to spend time, not something to pass through.
- Process: audit a level by naming its elements, and treat "that could be a landmark" as "it is not one yet". Make the
  plan (top-down) legible first, then check in play (section) that each element still reads.
- Playtest without the HUD, minimap or GPS-style guidance. Turn-by-turn navigation is egocentric and, the speaker
  says, has been shown to lower route memory; without it players map the space itself.

## What the kit took

- `ci/godot/templates/placement_check.gd`, two new groups. `landmark`: `landmark_still` (not a moving body, not under
  a `PathFollow3D`, and did not move in 30 physics frames) and `landmark_seen` (in view ahead from at least two
  separate stretches of the level's routes). `route`, a `Path3D` the player travels: `landmark_ahead` (walked each way,
  unless `one_way`, a landmark is in view ahead on at least 25% of it). Seen means within a 90 degree view along the
  way the player walks, from 1.6 m eye height, with a ray to the landmark's `Marker3D` children that hits nothing.
- `tests/placement-fixture/wayfinding/forest.tscn` and `rule_cases/wayfinding.tscn`, checked by
  `tests/Test-Placement.ps1`: a drifting balloon, a tower seen along one stretch and a trail with nothing ahead on the
  way back give exactly those findings; a canopy over the trail and a beacon behind the start fix them.
- `godot-game-design` section 7 (the audit table, plan then play, playtests with `--capture=nohud`), the `--capture=nohud` row in
  `godot-automation-hooks` (capture mode: `godot-debug-tools`), rows in `godot-data` section 6, and the eval `evals/lost-in-level`.

## Numbers

- The fixture by hand and by the checker agree: under the canopy (3 to 6 m up, 25 to 35 m along a 60 m trail) the
  tower's top (30 m up, 100 m from the start) is hidden from 11.25 m to 31.6 m, so it is seen at 0-10 m and 32-60 m
  (2 m steps), 21 of 31 points, 68%.
- Five broken variants of the checker each fail the self-test: the checker from before this change, no view cone,
  every point counted as a sighting, no watch for movement, `one_way` ignored.
- Cost: 4 routes of 1,000 m walked both ways with 10 landmarks and 200 walls (about 20,000 rays) took 77 to 443 ms on
  a shared 4-core 2.1 GHz Xeon, Godot 4.7.2 headless.

## Not taken

- No numbers come from the talk: two sightings, 25% and the 90 degree view are the kit's defaults, set per game.
- Directional landmarks and crisp edges: judging how different a landmark looks from each side, or how sharp an edge
  reads, needs pictures and a person; they stay in the skill's audit.
- An automatic squint test: districts need the designer's labels before a picture can be scored. The skill asks for a
  top-down view looked at small instead.
- Nodes as places: whether a hub is worth staying in is a design judgement, not a measurement.
- A kit switch to hide the HUD: `--capture=nohud` belongs to the game, like `--autoplay`.
