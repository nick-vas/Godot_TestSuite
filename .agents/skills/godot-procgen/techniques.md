# Technique notes (godot-procgen reference)

**Tracery.** Write grammars in Tracery's JSON format (`{"origin": ["#name# the #title#"], "name": [...]}`) and try them
with the minified build its author recommends, `js/tracery.min.js` from the repository (Apache 2.0; it bundles the almond
loader, MIT or new BSD, whose header must stay). That build picks with `Math.random` and cannot be seeded, so in the game
read the same JSON with the seeded expander below (plain `#symbol#` references; Tracery's modifiers such as `.capitalize`
and its `[actions]` need code of their own). In a web export only, where reproducing a run does not matter, the minified file
can run in the page: add `<script src="tracery.min.js"></script>` to the preset's `html/head_include`, ship the file next to
the exported page, and call it with `JavaScriptBridge.Eval("tracery.createGrammar(...).flatten('#origin#')")`.

**WFC for maps** (Brian Bucklew, Caves of Qud): small samples (8x8 to 16x16, N = 3; bigger ones mostly repeat and cost
memory and time); symmetry 1 when up matters, 8 for top-down buildings. A third "interior" colour beside wall and floor gives
closed rooms and tells later passes what is inside. Large outputs look the same everywhere: split the map into regions first
and fill each from its own sample. Keep doors and props out of the sample (each extra colour cuts the overlaps, and the output
repeats): generate walls, then join separate regions with A\* and put a door where a path crosses a wall.

**Tables of tables** (Caves of Qud's population tables, kept as data): an entry is an item or another table; a table picks
one entry by weight or takes each entry; each entry has a count (`1-2`) and a chance (`50%`), so one roll gives a boar or a
whole goatfolk camp. Placement hints on an entry (`outside the door, radius 2`) are read by spatial callers and ignored by
others. Look tables up from specific to general (this faction's, this region's, the default) and specialise only the ones
that matter.

**Histories** (Caves of Qud's sultans): an entity is a bag of properties (name, birthplace, one domain such as ice) and
events change them. Pick events at random and write the cause afterwards from the state (`the persecution of #ally#` when
it has an ally); an event with no state to use sets some (treated with cats: cats are now friendly) for later events. Start
with little state: one recurring domain threads a life together, and players infer the causes.
