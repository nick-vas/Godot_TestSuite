# Accessibility in play: reading, captions, vision, motion, assists (godot-ui-accessibility reference)

Lessons from GDC talks, in the kit's words; who said what, and what was left out, is in
`${CLAUDE_PLUGIN_ROOT}/docs/gdc/folds-accessibility.md`. The menu rules are in `SKILL.md`; these cover the game itself.

## Long text (codex, letters, narrative games)

From Joseph Humfrey (inkle: 80 Days, Sorcery!, Heaven's Vault):

- About 5 to 15 words a line; past about 15 the eye loses the start of the next line (WCAG 1.4.8 says at most 80
  characters). Full-width text along the bottom of a wide screen reaches 30 words a line: give it a narrower column.
- A familiar typeface over a stylised one for anything long, wide margins, space between paragraphs, and an indent on
  the first line of each paragraph (80 Days found it kept players from losing their place).
- Keep earlier text on screen, dimmed, and draw the current passage brighter: the brightness says what to read now,
  the rest gives context.
- Text revealed letter by letter or word by word is quick enough never to hold back a fast reader, and never needs a
  held button to speed up; test with slow and fast readers. Set `VisibleCharactersBehavior` to
  `TextServer.VisibleCharactersBehavior.CharsAfterShaping` on the `Label` or `RichTextLabel`: the default lays out only
  the visible part, so a word jumps to the next line as it grows (a 4-line label measured 1, 1, 2, then 4 lines as it
  filled, in Godot 4.7.2).
- Choices appear a moment after the text, under a second, and fade in slowly, so the eye reads the text first.
- Many short screens, each needing a press, slow reading down (Sorcery's rapid choices made an action scene feel
  slower); dialogue lines that may overlap, the new one appearing while the last is still up, sped Heaven's Vault up.

## Captions: which sounds, and which wins

- Caption every sound the player must react to: hazards, ordinary enemies' attacks, not only the boss wind-ups.
  Borderlands 3 captioned only urgent sounds not shown elsewhere, and reviewers marked it down (Andrew Baer). Emotion
  and sound effects inside dialogue count too.
- The list of sounds that carry information comes from the players who know the game best, not the designer: Evolve's
  accessibility lead did not know spotters made a noise until the balance testers told her (Tara Voelker).
- Subtitles have a priority: a story or tutorial line is never pushed off by a combat bark ("Reloading!"); the same
  priority decides which voice line is heard (`godot-audio`).
- Subtitle channels: the player can turn sources on and off (the main character, crowds, a loudspeaker), as in We
  Happy Few, so a busy scene can be thinned to what they can follow. Music can be captioned too ("[upbeat tempo]").
- Someone speaking who has no name still shows who: a small speech icon over them.
- Playtest with the sound off, by people new to the game: the team knows the cues and fills them in without noticing
  (Karen Stevens).

## Seeing it

- Tiers such as loot rarity differ in more than hue: Borderlands 3's loot beams grow taller, wider at the base and
  denser in particles with rarity, the top tier gets a minimap icon, and each rarity drops with its own sound.
- Fix the elements that fail (another icon, shape or effect), not the whole screen: a filter shifts colours that were
  fine. Evolve retrofitted three extra versions of each problem effect; afterwards concept art showing two states that
  differed only in colour was sent back before anything was built. Effects that mark where a hit lands get a sharp,
  high-contrast edge.
- Red on black darkens for protanopes: pure red measures 5.3:1 against black, 3.3:1 through the protan simulation, and
  #CC0000 falls from 3.6:1 to 2.4:1 (computed with `shot -ColorVision`'s matrix). Madden's dark red play arrows
  vanished (Karen Stevens).
- To check a colour fix with people, show the screen and ask, without hints, how many colours they see and where (Karen
  Stevens: Madden went from about a third counting right to everyone, over several rounds).
- A high-contrast layer: a `ColorRect` on a `CanvasLayer` between the background and the foreground, transparent by
  default, and a slider that tints it toward black or white (Ian Hamilton: Epic Eric's took 15 minutes).
- HUD placed in the world gets an enlarge option: Madden's doubled the icons over players and moved the kick meter from
  the field to a fixed place on screen, where it no longer shrinks and wanders with the camera (Karen Stevens: about a
  day of work).

## Motion

- Head bob and camera sway are a 0 to 100% slider, not only off and on: a multiplier is cheap when it is asked for
  early (Andrew Baer: Borderlands 3's took about 30 minutes, because QA raised it in pre-production).

## Assists

- Debug and tuning switches (invincibility, slow motion) belong in the settings, not stripped before release (Ian
  Hamilton): with them, a player who plays by voice commands can play Celeste, through practice and persistence, as it
  was meant.

## Narrating your own menus

When the game speaks its menus itself (`DisplayServer.TtsSpeak`) rather than through the screen reader:

- Say the control's name, what it does and its current value ("Subtitles, on"); while a slider moves, the new number
  alone is enough. Text that cannot take focus is read when the screen opens. Compare with Windows Narrator or
  VoiceOver.
- Speak at the widget level (every button, slider, table row) so new screens are covered and nothing goes stale as
  recorded lines do; offer the speech rate (`rate`, up to 10), since screen-reader users listen fast (Karen Stevens).
