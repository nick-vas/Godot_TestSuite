# {{GAME}}: tech debt at the vertical slice

<!-- Written at the end of the vertical slice (gate slice.debt checks that this file exists). A slice is never feature
     complete: list what it hacked, stubbed or never started, and what each costs to finish for the whole game, so the
     slice verdict can say whether production fits. Update it at each milestone; delete rows when the work is done. -->

Weekly hours: 10 (from plan/plan.json `weeklyHours`)

## Systems

State is one of: **hacked** (works in the slice, will not survive production), **stubbed** (faked or hard-coded),
**slice-only** (works in the slice's small area; not yet tried at the size of the whole game), **not started**.

| System | State | What production needs | Estimate (hours) | Risk at full size |
|---|---|---|---|---|
| Example: level streaming | slice-only | Load and unload rooms around the player; the slice has two rooms, the game forty | 30 | high: never run with more than two rooms loaded |
| | | | | |

Estimate the work at the size of the finished game, not the size of the slice: fixing a system in one small area does
not tell you what it costs everywhere.

## Placeholders

Every stand-in asset or text, labelled as one in the game. Production keeps this list; at beta only a small part of the
content may still be here.

| Placeholder (file or content) | What replaces it | Who makes it | Due (milestone) |
|---|---|---|---|
| | | | |

Mark each stand-in file in `assets.json` too (`"placeholder": true`, `"due": "yyyy-MM-dd"`), so `doctor` and `status` count
them and `doctor` fails once one is past its date.

## Total and threshold

Total: 0 hours, about 0 weeks at the weekly hours above.

Accepted: the most debt production can absorb, decided before the verdict (for example "under 20% of production's
timebox"). Over it, the slice verdict is more slice time, a cut from the scope ladder, or PIVOT.

## Performance at production density

The busiest slice scene, filled the way the finished game will fill it (draw distance, level of detail, crowds,
effects), and its frame budget (gate slice.budget):

Scene: res://...
Budget: 16.7 ms p99 at 1920x1080
Last `bench` result: (paste fps and p99 from bench-results/bench.json)
