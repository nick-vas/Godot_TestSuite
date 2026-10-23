# Intentional mistakes (godot-game-ai reference)

An enemy that always does the best thing is not fun to play against: aim, timing and numbers are where a computer beats
a person without trying. The craft is losing well, with mistakes the player reads as the enemy's character, not as a
bug. The classic text is Lars Lidén, "Artificial Stupidity: The Art of Intentional Mistakes", in *AI Game Programming
Wisdom 2* (Charles River Media, 2003, often dated 2004; two papers that cite it place it in the second volume, not the
2002 first).

**What is verified here, and what is not.** The chapter itself could not be read from this machine (2026-10-23: the
author's site has a self-signed certificate and the archived copy did not load), so nothing below quotes it directly.
Two sources that cite it were read: Trazzi and Yampolskiy, "Building Safer AGI by introducing Artificial Stupidity"
(arXiv 1808.03644, 2018), which says Lidén's NPCs must "move before firing" (rolling when the player enters, so the
player has time to see that a fight has started) and "miss the first time" (to show where the attack comes from without
hurting the player); and Mick West, "Intelligent Mistakes: How to Incorporate Stupidity Into Your AI Code" (Game
Developer, 2009), which lists the chapter as a resource and puts the idea as "The computer has to throw the game in
order to make it fun." The other points in the list are how the chapter is commonly summarised, written in the kit's
words; check them against the text before quoting any of them.

## The rules, as tests

Each mistake is a number in data and a test in the game's suite, so a balance pass cannot quietly remove it.

| Mistake | In the game | Test |
|---|---|---|
| Move before firing (verified) | An enemy that sees the player first moves, turns or animates for a set time, then attacks | No damage within the telegraph time of first sight, over seeded runs |
| Miss the first time (verified) | The first shot of an encounter lands near the player, where it is seen and heard (`Aim.Scatter` with a wider cone for shot one) | Shot one never hits, over 1000 seeded encounters; later shots hit at the designed rate |
| Be visible, warn the player | Enemies enter where the camera sees them, with a sound or bark before the threat (`godot-playtest`: hit by what they never saw coming) | An attack from outside the view is preceded by its cue |
| Poor aim on purpose | Accuracy is a designer number per enemy type, not the solver's perfect lead (`aiming.md`) | Hit rate per type within its band |
| A few attackers at a time | Others circle, reload or take cover while one or two attack (attack slots handed out by one system, like the role assignment in `SKILL.md` section 4) | Never more than N attackers at once |
| Tell the player what you are doing | Barks for reloading, flanking, throwing (`godot-narrative`) | Each such action raises its bark event |
| Ease off at the last moment | When the player is nearly dead, aim and timing slacken a little, never visibly (`godot-progression`: adaptive difficulty moves slowly) | The adjustment stays inside its bound and is logged |
| Vulnerabilities on purpose | Reloads, recoveries and boss patterns leave openings a player can learn | Each opening lasts at least its designed time |

## Keep the mistakes plausible

- A mistake must look like the character's, not the code's: a guard that misses because it fired on the move, not one
  that stares at a wall. Mistakes the player sees as bugs are what reviews call dumb AI.
- Make the mistake, never the decision, random: the enemy still chooses well and then executes imperfectly, so its
  intent stays readable and testable (`Utility.cs`, `BehaviorTree.cs` decide; `Aim.Scatter` misses).
- Seed every mistake (`godot-determinism`), so a replay or a failing test shows the same miss.
- Tune by watching players, not by win rate alone: a playtest's deaths with no visible cause (`godot-playtest`) mean the
  warnings are too quiet, whatever the numbers say.
