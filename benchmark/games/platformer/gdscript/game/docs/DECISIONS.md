# Decisions

- 2026-10-01 Prototype verdict: PROCEED. The jump feels fair with coyote time and a buffered press.
- A side view of a 3D world, not 2D: the kit's placement check works on 3D levels, and every tuft of glowmoss is checked
  against the climber's real reach.
- Movement is plain code (Movement) that moves the body by the average velocity of each tick, so a jump is the same
  height at 30, 60 or 120 ticks a second.
- Screens are children of Main rather than scene changes, so the save and the loaded tables live in one place.
