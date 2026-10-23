# Lanternfen

**Pitch:** a duel of lantern-keepers in a fen: play wisps and rites from a deck of twenty cards, out-think five rivals
one after another, and put out each one's light before it puts out yours.

**Pillars:** every turn readable at a glance (named phases, a log line for each); rivals that play by the same rules as
you; a duel decided in a few minutes.

## Features

### F1 The turn
Priority: must
Done when:
- a turn runs Draw, Main, Clash and End; Clash is skipped when the keeper has no wisp; a test covers each transition

### F2 Cards
Priority: must
Done when:
- eleven cards in data/cards.json, wisps that strike across their lane and rites that act once, checked by the data runner

### F3 Rivals
Priority: must
Done when:
- five rivals with their own decks and AI weights; a utility AI plays only legal cards, and the player's deck can beat each

### F4 Fairness
Priority: must
Done when:
- the shuffle follows the duel's seed alone; an empty deck costs light, so every duel ends

### F5 Menus, pause, settings, saves
Priority: must
Done when:
- menu, rival select, pause, volume and language; wins and losses are saved, and Continue carries on a duel; old saves still load

### F6 Languages
Priority: should
Done when:
- English, French and German, every visible text through tr()
