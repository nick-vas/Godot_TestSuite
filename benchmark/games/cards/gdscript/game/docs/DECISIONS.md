# Decisions

- 2026-10-01 Prototype verdict: PROCEED. Three lanes are enough for a choice every turn, few enough to read at a glance.
- The rules live in plain classes (Duel, Keeper, Ai), so tests play whole duels without a scene; the game node only paces them.
- A turn is named phases, each transition logged ([Turn] 3 Main -> Clash) and signalled; nodes animate, never decide.
- Cards, decks and rivals are data checked by the data runner; deck legality (20 cards, two copies at most) is a test.
- Each duel shuffles with its own seeded generator, so a --seed replays a duel exactly.
