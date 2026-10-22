# Assassin's Creed Origins: Monitoring and Validation of World Design Data

- Speakers: Nicolas Routier (as transcribed; possibly "Routhier"), design technical director at Ubisoft Montreal, with
  Kevin Coughlin, who built the system with him, for the Q&A. Tests also written by Roland Levesque and Rémi
  Toupin-Godet (Whisper spellings, unchecked).
- Year: not stated. Implied 2018: the first report shown is from 2016, a later one from five months before the game's
  October 2017 release, and the talk looks back on the shipped game.
- Video: https://www.youtube.com/watch?v=VVq_hgaX8MQ

## Lessons

- Everyone breaks placed content, often without touching the place that breaks: a designer drops a shield prop and an
  AI node ends up off the navmesh; a prop modeller in another studio fixes that prop's collision and the same happens in
  every location using it; an engine fix to navmesh generation removes navmesh from every slope; a procedural rule or a
  build machine loading data in the wrong order puts trees on roads.
- Code is an input of the data tests. If gameplay code lowers the zip-line angle it can animate, zip lines that passed
  must now fail, so "we always need to test with the latest code."
- Each object type gets objective pass/fail rules a computer does well. Zip line: a shape cast under the rope finds
  anything in the player's way, and the rope's angle is compared with the threshold. Chest: oriented so it can be
  looted. Boat spawner: over water. AI network: a ray 50 cm down from each node finds navmesh, each edge has a navmesh
  path, and every station in a spawned NPC's schedule is reachable from its spawner. Locations: everything inside a
  location's footprint is compared with a design spreadsheet (expected one high-value item, found none).
- Each result names the object, says in plain English what is wrong and links to the editor with the camera on it; a
  map view put a pin on each error.
- The daily summary's most useful column was the change per object type since the day before: "ladders +500" told the
  technical director the scope of a regression before anyone came to his desk.
- A bug found once becomes a permanent rule: one wall torch out of the player's reach led to a downward ray from every
  wall torch, every night until ship, instead of a one-off manual pass.
- False positives waste the receiver's time and kill trust in the system, so a new test is first tried on a known case
  with a colleague as a "guinea pig to test the test". Single instances can be exempted from one test.
- Gates at submit time do not replace the full nightly snapshot: data fine on day one breaks on day ten through other
  changes. Twelve separate report emails a day was too many; one summary would do.

## Numbers from the talk

500+ locations in over 120 km² (Syndicate's London, 12 km², is about 10% of it). 228 zip lines at two minutes each is
one tester's full day; 22 object types and 200,000+ placed instances would take 20 testers two months, once. The
first report (2016) covered 4 object types, with about 1,000 ladders of which 75% had a problem; five months before
ship, 18 types and 1,300 ladders with 7 left. About 700 wall torches. One build machine, three hours a night, mostly
loading the world: 12 reports, 150,000+ pathfinding tests, a million AI nodes and edges, 5 million procedural assets.
About four errors were left at ship.

## What the kit took

- `ci/godot/templates/placement_check.gd`: a GDScript checker a game copies into its tests. By node group: `ai_point`
  (navmesh within 0.5 m below, a path to each linked point), `interactable` (ground within the player's reach),
  `zipline` (a capsule swept under the rope hits nothing; angle under the limit). Limits are set from the game's
  constants, one line per finding, exemptions through `placement_skip` metadata with a reason, and a summary per type
  with the change since the last run.
- Why a copied helper and not a new runner: it runs inside the GUT runner every game already has, so it needs no
  detection, no runner and no new JSON fields, and the test reads limits as `Player.REACH`, so renaming the constant
  breaks the test at parse time instead of silently falling back to a copied number.
- `tests/placement-fixture` and `tests/Test-Placement.ps1`: a level with an AI point 2 m above the navmesh, a torch
  3.5 m above the ground (reach 2.5 m) and a zip line through a crate gives exactly those three findings with their
  values; the other rules are broken once each in `rule_cases/`; moved and exempted, the level passes.
- `godot-data` section 6 ("Placed objects") and a pointer from `docs/data.md`.

## Measured here (Godot 4.7.2, headless, 4-core 2.8 GHz Xeon)

- NavigationServer3D answers `map_get_closest_point` and `map_get_path` under `--headless`. With one region added at
  run time, the first answer came at physics frame 4 or 5 in a bare `-s` script; in a GUT run the first level needed 9
  to 11 physics frames and the next 3 or 4. Queries before the first sync print an engine error.
- Two traps the fixture caught before the checker reported anything: before sync, `map_get_closest_point` returns
  (0, 0, 0), so a readiness probe at a region centred on the origin looked ready early and every AI point read as
  off-mesh; and `map_get_path` to a point on another navmesh island returns a non-empty path that stops 12 m short.
- About 7 to 14 ms per 1,000 checked nodes of one type (one navmesh polygon, so real path queries cost more).

## Not taken

- The location test against a design spreadsheet and NPC schedule reachability: both depend on a game's own model of
  locations and schedules; `path_to_link` is the mechanism a game would reuse.
- Editor links and a map of pins: the finding line's scene, node path and position locate the node.
- Splitting counts by region team, and a velocity chart: a game with teams can group by scene folder.
