# Commissioning music (godot-audio reference)

When the game's music comes from a composer the team hires rather than a library, the request decides whether the
composer the team wants says yes. From the Untold History interviews (`${CLAUDE_PLUGIN_ROOT}/docs/studio-lessons.md`,
lesson 30): Katsutoshi Eguchi won Michael Nyman by sending him the game to play, "We sent him a copy of D no Shokutaku
while he was still in England, and he played it and thought it was good", and by explaining "why it had to be Michael
Nyman, over and over again".

- **Send something playable.** A build (`export -Preset ...`) or, when a build cannot travel, a video of play with the
  game's own sound; a page of description is not enough.
- **One page of "why you".** Which of their pieces fits which moment of the game, and what the game needs that their
  music does.
- **Say what the music must do in the game.** The adaptive plan from section 2 of the skill (sections, layers, stingers,
  loop points, BPM for `NextBar` switches), the format (Ogg Vorbis for music) and the loudness target (section 7), so the
  delivered files work without a second pass.
- **Rights in writing.** Who owns the music, where the game may use it (trailers, the soundtrack sold apart), and the
  credit line; record it in `assets.json` (licence `proprietary` or the agreed one) so `credits` lists the composer.
