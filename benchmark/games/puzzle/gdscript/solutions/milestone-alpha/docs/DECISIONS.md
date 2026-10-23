# Decisions

- 2026-10-01 Prototype verdict: PROCEED. Sliding until a wall makes even small boards surprising.
- Screens are children of Main rather than scene changes, so the save and the levels live in one place.
- Levels are data (data/levels.json) checked by the data runner, and a test holds each par to the solver's answer.
- The daily drift's generator draws only from its own seeded generator, one per attempt, so a seed is a bug report.
