# Make the Trailer Before the Game: A Marketing-First Way to Prototype

- Speaker: Derek Lieu, game trailer editor (Whisper writes "Derek Liu"; the same speaker as
  [capturing-footage-for-trailers.md](capturing-footage-for-trailers.md)). He quotes interviews with Lucas Pope, Greg Kasavin
  (Supergiant), Daniel of Eastshade Studios, "Eka" (also "Echo") of Outerloop Games, "Jeff" of Mediatonic and "Gwen" of the
  Soup Pot team ("Satell Studios slash Chicon Club" in the transcript); those names and
  studios are doubtful.
- Year: not stated. Viewfinder, Dredge and Thirsty Suitors (all 2023) are discussed as released games, so probably GDC 2024
  (inferred).
- Video: https://www.youtube.com/watch?v=10YhD9HMsPA

## The talk's lessons, in short

1. **Ask what the trailer is while prototyping, not at the end.** Late in production the question "what do I show?" is a
   bad sign: the less clear the answer, the less marketable the game. Lucas Pope drops a prototype when he cannot imagine a
   cool trailer for it, and asks whether it can be pitched without comparing it to other games or letting someone play for
   hours.
2. **A trailer forces the right questions**: what the game looks like *while being played*, how fast its selling points can
   be shown, how it looks different from its inspirations, and how hard it is to follow when watching rather than playing.
3. **Order: genre, hook, content.** The first five seconds place the game in a genre; most of the trailer shows why it is
   different; bosses, skins and counts come last, if at all. In his words: "establish a genre. Explain your hook and then get
   the content if there's time." His longer scene template: opening shot, premise and mechanics, escalation, climax,
   variety and scope, ending.
4. **Mechanics need visible feedback.** Viewers look for what on screen shows the player's action; ask of every mechanic what
   it looks like in the trailer and what change would make it visible. Design for watchers too: Firewatch's dialogue
   highlight shows what the player is weighing, a face-button choice (Walking Dead) does not.
5. **Three standout moments.** A common AAA prompt; people remember a few moments, not a whole trailer (Half-Life: Alyx's
   shotgun shells on a shelf). Eastshade's team built quests and a scene for Songs of Glimmerwick because the trailer needed
   them.
6. **It aligns a team.** Supergiant's Transistor was floundering until a month-long tone video (script, music, art,
   voice) made the world specific; Kasavin: "work just goes slowly if you don't know what you're building when you're
   building it."
7. **Cheap formats first, timeboxed.** A written description (player, fantasy, mood, emotion, loop steps, scenes in order),
   then a mood board or ripomatic, an animatic, prototype clips, a vertical slice. Two weeks (Soup Pot) to a month
   (Outerloop) for early trailer concepts; throw the result away once it has made its point. Check it by showing it to
   someone: you see its problems through their eyes, even if they say nothing.
8. **Q&A:** put the store page up as soon as the art style is settled.

## What the kit took

- `ci/godot/templates/plan.json`: gate `prototype.trailer`, automatic (`file:docs/TRAILER.md`), after `prototype.setup` and
  before the loop is built and the verdict.
- `ci/godot/templates/TRAILER.md`: the five-line written description, the genre/hook/challenge/depth/content table, the six
  scenes with "in the game yet?", three standout moments, a mechanics table with an on-screen feedback column (empty cells
  are design work, `godot-juice`), and the checks (show it to someone; pitch without comparisons; Pope's test into the verdict).
- `.agents/skills/godot-game-plan/SKILL.md` explains the gate; `.agents/skills/godot-store-page/SKILL.md` starts the launch
  trailer from this script; `docs/plan.md` lists the gate under "Rules baked into the gates".
- `tests/Test-Plan.ps1`: on a fresh plan the prototype gate is open, automatic and ordered before `prototype.loop` and
  `prototype.verdict`; `plan -Do done` refuses it (`auto-gate`); it turns done when `docs/TRAILER.md` exists; the template
  keeps genre before hook before content, three moment slots and the feedback column; templates the two skills name exist.
  Against the previous plan.json and without the template it fails 11 checks.

## What it did not take, and why

- **Mood boards, ripomatics, animatics, prototype clips:** they need editing or art skills and the developer's judgement;
  the written script is the step an agent can draft with the user. The template mentions the timebox for the rest.
- **Checking the script's content** (are the cells filled?): like the other `file:` gates only existence is checked; a
  filled-in script is the developer's honesty, and the verdict is where Pope's test is applied.
- **Genre viability research:** he says a trailer does not help with it; `concept.market` already covers comparable games.
- **Store page timing:** already in `launch.store` and `godot-store-page` (months before launch).

## Doubts in the transcript

"Noteplip" is Noclip (the documentary channel); "Atreya" is "a trailer"; "Rippomatic" is ripomatic; "Gen Z" is Jen Zee and
"Logan" Logan Cunningham (Transistor); "Thirsty Shooters" is Thirsty Suitors; "City Boulder" is city builder. The Soup Pot
team's name and Mediatonic's interviewee are uncertain and not relied on.
