# Decisions

- 2026-10-01 Prototype verdict: PROCEED. The core loop (aim, dodge, keep the combo) is fun in one screen.
- Screens are children of Main rather than scene changes, so the save and the loaded tables live in one place.
- Collisions are simple rectangles checked in code at a fixed 60 ticks, so a seed replays a run exactly.
