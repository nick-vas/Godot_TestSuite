# {{GAME}}: jam design document

<!-- The game-jam profile of GDD.md: days, not weeks, and under three pages. Copy it to docs/GDD.md; `status` reads the
     "### F<number>" features the same way. Unsure whether a feature fits? It does not: put it under "Cut list". -->

## Pitch

One sentence: what the player does and why it is fun. The jam's theme, and how the game uses it.

## Platform and language

Browser build? Answer first. Godot 4.7 cannot export C# to the Web, so a browser jam is made in GDScript
(`godot-mobile-web`). Desktop only: C# or GDScript.

## The 30-second loop

What the player does in the first 30 seconds, and again in every 30 seconds after.

Win: ...  Lose: ...

## Must-haves

### F1 Example must-have
Priority: must
Fun: challenge
Done when:
- An observable result a test, flow or screenshot can check.

## Cut list

Nice to have, added only once every must-have works, in this order:

1.

## Days

| Day | Goal |
|---|---|
| 1 | The riskiest part (usually the feel of the core action) proven with plain shapes; coloured rectangles ship fine |
| 2 | The loop playable with win and lose |
| ... | Must-haves, one at a time, each with its test |
| Second to last | Exported to the jam's platform and launched (`export -Run`); a private upload to the jam site |
| Last | Fixes only; submitted with an hour or more to spare |

## Risks

| Risk | Likelihood | Mitigation, and the day it is retired |
|---|---|---|
| The core action does not feel good | High | Prototype it on day 1; everything else depends on it |

## Credits

Every asset made by someone else goes in `assets.json` with its source and licence; `credits` builds the credits page
(`godot-credits`).

## Submission

- [ ] The build the jam page links to is the one that was launched with `export -Run`
- [ ] Controls, the goal and the credits are on the jam page and in the game
- [ ] Submitted before the deadline, with a margin
