# Goal-Oriented Action Planning: Ten Years of AI Programming

- Speakers, as transcribed: Peter Higley (Monolith Productions, Middle-earth: Shadow of Mordor), Chris Conway (Crystal
  Dynamics, Tomb Raider 2013 and its sequel), Eric Jacopin (a research centre of the French military academy, as he puts
  it). The captions garble the studio and game names ("Mortimer Productions", "Shadow of Mortar"); the speakers' names
  are transcribed the same way each time, but their spelling is not confirmed.
- Year: not stated. About 2015, inferred: Higley says GOAP is ten years old, having started on F.E.A.R. in 2004, Shadow of Mordor is
  Monolith's latest title, and Rise of the Tomb Raider is in alpha.
- Video: https://www.youtube.com/watch?v=gm7K68663rA

## What the talk says

- **Higley: what GOAP is, and keeping it cheap at Monolith.** Goals have a fixed priority and a quick validity check.
  A* searches from the goal's desired world state back to the current one, with a heuristic of how many variables are
  still unsatisfied. Planning cost grows with the number of world-state variables: about 40 flags that were never true
  together (cower and the like) became one enum, leaving about 10 variables. Shorter plans are found faster, so logic
  moved out of the planner. Drawing and sheathing the sword became an animation transition, which made plans one action
  shorter. Goal lists were split by awareness level (ambient, suspicious, alert) and swapped when it changed. An
  investigation system now takes every orc that saw a disturbance, picks who searches (the closest, or a captain) and
  hands out roles: lead investigator, watch his back, dismiss. Each orc's planner only plans for its role, which saved
  CPU and made new roles easy to add. Up to 50 AIs could plan in one frame, and the planner was never throttled. In the
  Q&A he says throttling the systems whose events trigger replanning ended up throttling the planner too.
- **Conway: extensions at Crystal Dynamics.** His main one is situational costs: an action's cost depends on the
  situation, and the walk to a target costs its distance. In his example melee costs 1, but "the goto has a cost of 20,
  and the planned cost ends up being 21"; ranged costs 10 plus a walk of 1, so the NPC shoots from afar. He prefers this
  to hard range limits, because the planner still copes when ammo runs out or the melee weapon breaks. Other extensions:
  motives (Sims-like needs) that gate goals; several candidate plans per goal; requirements that come from the object
  being used; parent actions that watch their children (ending a walk early when line of sight appears); open-ended
  actions that report a remaining cost so a cheaper plan can replace them; success statistics that tune costs; and a
  designer-built behaviour graph for choosing goals. For debugging, he shows the current plan and step, the goals
  rejected at the last plan with their reasons, and a timestamped history. On-screen and nearby NPCs plan more often
  (Q&A). Tomb Raider lets only so many NPCs investigate, and delays an event by distance so the closest plans first (Q&A).
- **Jacopin: logs from F.E.A.R. (his modified SDK), Shadow of Mordor and a Rise of the Tomb Raider alpha.** Plans are
  mostly one or two actions, with a few of three or four. His advice: "Design short plans. I won't say that enough
  again. 3 actions at most". Shadow of Mordor reached up to 150 concurrently active NPCs (about 400 on screen in one
  fort). With a sliding window, one session crossed the 50-plan limit within 0.4 s; it usually took 2 to 3 s. A few
  actions account for most planning: by his count, 8 actions make up 80% for F.E.A.R., 14 for Mordor and 4 for the Rise
  alpha. He advises limiting how many NPCs may call the planner.

## What the kit took

- `examples/breakout/src/Breakout.Core/Ai/Goap.cs`: `GoapPlanner.Plan` takes an optional `costOf` function that prices
  each action once per call from the current situation. Fixed `GoapAction.Cost` stays the default, and negative or NaN
  costs throw. Existing calls are unchanged.
- `examples/breakout/tests/Breakout.Core.Tests/AiTests.cs`: `GoapCostsFollowTheSituation` uses Conway's numbers. At 2 m
  the plan is walk then melee (3 against 11). At 20 m it is move into range then shoot (11 against 21). At 20 m with no
  ammo it walks in to melee. With fixed costs the plan is melee at every distance (2 against 11). If the planner ignores
  `costOf`, the test fails at 20 m (it expects ranged and gets melee).
- `.agents/skills/godot-game-ai/SKILL.md` section 4: situational costs; short plans; folding exclusive flags into an
  enum; a planning cap per frame with the Mordor and Jacopin numbers; group decisions in a separate role-assignment
  system. Each comes with its speaker.

## What it did not take, and why

- Motives, multiple plan candidates, situational requirements, parent monitoring and open-ended actions with a
  remaining cost: each needs a stateful plan executor, and Breakout's planner is a pure search. Worth a later change if
  a game needs it.
- Learned costs from success statistics: Conway raises open questions himself (whether early-game results should affect
  late-game NPCs).
- The debug view: the skill already asks for decisions recorded to a ring buffer.
- Jacopin's planning-speed comparison with HTN games (Killzone 3, Transformers 3), and the Q&A remark that Killzone 3
  ran its AI at 5 Hz: the captions do not make the speaker or the units clear.
