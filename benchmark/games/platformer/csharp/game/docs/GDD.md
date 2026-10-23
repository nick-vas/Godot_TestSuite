# Glowmoss Ridge

**Pitch:** a side-on platformer: climb five stretches of the ridge, gather glowmoss on the way, stomp the beetles that
guard it, and light the beacon at the end of each stretch.

**Pillars:** a jump that forgives (coyote time, a buffered press); every level readable from the first screen; every
touch felt (a pop, a sound, a shake).

## Features

### F1 Running and jumping
Priority: must
Done when:
- the climber runs, jumps a designed height, hops short on an early release, and keeps the same arc at any tick rate

### F2 Forgiveness
Priority: must
Done when:
- a jump 0.1 s after leaving a ledge still counts, a press 0.2 s before landing jumps on landing, one press is one jump

### F3 Hearts, beetles and thorns
Priority: must
Done when:
- three hearts per level; thorns and a beetle's side cost one, then 1.5 s of safety; landing on a beetle stomps it; a fall
  costs one and returns the climber to the last checkpoint

### F4 Levels and glowmoss
Priority: must
Done when:
- five levels from data/levels.json, each a scene in levels/, every tuft of glowmoss within a jump of the ground

### F5 Menus, pause, settings, saves
Priority: must
Done when:
- menu, continue, pause, volume and language settings; the furthest level and the best score are saved, old saves load

### F6 Languages
Priority: should
Done when:
- English, French and German, every visible text through tr()
