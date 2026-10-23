# Frostmote

**Pitch:** a sliding puzzle on ice: steer a mote of frost that only stops at walls and snow, gather every spark to
open the exit, and reach it in as few moves as you can.

**Pillars:** one rule, many surprises; every level fair (a solver proves it); no dead end left unexplained.

## Features

### F1 Sliding
Priority: must
Done when:
- the mote slides until the tile ahead is a wall; snow stops it on the snow; a move that goes nowhere is not counted

### F2 Sparks and the exit
Priority: must
Done when:
- every spark the mote passes is collected; the exit opens, and stops the mote, once every spark is collected

### F3 Undo, restart and dead ends
Priority: must
Done when:
- undo takes back a move exactly; restart returns to the start; the HUD says when the exit can no longer be reached

### F4 Levels
Priority: must
Done when:
- eight levels from data/levels.json, each solvable in exactly its par, which a test proves with the solver

### F5 Daily drift
Priority: should
Done when:
- a level generated from the date (or --seed), the same for every player, always solvable in 4 to 14 moves

### F6 Menus, pause, settings, saves
Priority: must
Done when:
- menu, level select, pause, volume and language settings; solved levels and their best moves are saved, old saves still load

### F7 Languages
Priority: should
Done when:
- English, French and German, every visible text through tr()
