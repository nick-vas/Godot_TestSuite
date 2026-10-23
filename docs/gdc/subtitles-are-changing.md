# Subtitles Are Changing, Don't Be Left Behind

- Speaker: Ian, an accessibility specialist; the transcript gives only the first name. The surname Hamilton comes from
  the talk's attribution, not from the talk.
- Year: 2019, stated ("why am I here now in 2019").
- Video: https://www.youtube.com/watch?v=fVFgSkZtCio

## What the talk says (in our words)

- Most players use subtitles, not only deaf players: Assassin's Creed Origins measured just over 60% across platforms,
  which argues for on by default. Noisy rooms, poor speakers, unpredictable mixes and sleeping babies all count.
- Players complain about three things: size, contrast and how much text is on screen.
- **Size.** "So this is the figure to work to, at least 46 pixels at 1080p", taken from Amazon's 10-foot UI guidelines and
  Channel 4's subtitling guidelines (as transcribed). The talk does not say whether that is the font size or the letters' height.
  An art director may ship smaller subtitles as long as a setting lets players enlarge them.
- **Contrast.** Outlines and drop shadows break up over busy imagery and are hard for dyslexic readers; offer a solid
  box behind the text, ideally with adjustable transparency.
- **Amount.** At most two lines (three only rarely) and at most 38 characters a line, from the BBC's guidelines. Break
  lines where the sense breaks, by hand if need be.
- Good practice: the text matches what was actually recorded; everything is subtitled, the opening cinematic included
  (or the choice is offered before the first line); bottom centre; when several are shown, "just keep scrolling them up
  from the bottom and knocking the top one off", never one fixed row per speaker; the speaker's name in text, even when
  colour separates speakers, because subtitle users can be colour blind; an arrow for off-screen speakers and sounds
  (Minecraft cut its arrows back to what stereo gives so they would not be an edge online); enough time to read, editing
  the text only as a last resort; a plain sans serif in sentence case, not all caps; captions for important sounds; a
  live preview at the real size; presets when the options get numerous.
- VR: head-locked text strains focus, text pinned to the source gets lost; the promising approach follows the source
  while it is in view and snaps into view otherwise.

## From a second talk

Karen Stevens, "I Can't Hear You: Considering Deaf Gamers" (EA Sports, year not stated, 2018 or later since it shows
We Happy Few; https://www.youtube.com/watch?v=ijLaIZ2acSo), supplies the numbers Hamilton's talk lacks: subtitle text
about 3% of the screen height (32 px at 1080p), "the absolute minimum I will ever recommend is 28 pixels tall", with
strokes 3 to 4 px wide; one sentence per subtitle where possible; "160 to 180 words a minute is recommended"; two lines
ideal, never four or more; sound captions in brackets, short subject and verb; a 5% safe margin.

## What the kit took, and where

- `ci/godot/tools/textsize.gd`, `ci/godot/lib/TextSize.ps1`: text in the `subtitles` node group (or inside a node in
  it, hidden or not) is held to a subtitle size given at 1080p and scaled with each window's height. Under 28 px fails
  (Stevens' absolute minimum); under 46 px warns, because Hamilton himself accepts smaller defaults when a size setting
  exists, which the runner cannot see. Both are checked against the font size: the lenient reading, since Godot's
  default font draws capitals at about 0.74 of the font size. New `textsize.json` keys `subtitleGroup`,
  `subtitleMinPx`, `subtitleWantPx`; warning rule `subtitle-below-recommended` (`docs/json.md`, `docs/reference.md`).
- `tests/textsize-fixture/subtitles`, `tests/Test-TextSize.ps1`: 24 px fails (16.00 px against 20.74 at 1280x800), 36 px
  warns, 52 px passes, a label inside a hidden grouped container is measured, a 24 px label outside the group is not
  held to the subtitle size, and the same scene with `"subtitleGroup": "captions"` gives the same results.
- `examples/csharp/src/Example.Core/Ui/Subtitles.cs` with `SubtitlesTests.cs`: one subtitle per sentence, at most 2
  lines of 38 characters, lines as even as the words allow, the speaker's name glued to the first word of every
  subtitle, hand-made breaks kept when they fit, over-long words cut, `MinDuration` at 180 words a minute (name
  included), `Caption` in brackets.
- `.agents/skills/godot-ui-accessibility/SKILL.md`: size, layout, speaker names, captions, background box, preview and
  presets. The skill's earlier 40 characters came from Xbox XAG 104; it now says 38 (BBC, via Hamilton), noting that
  XAG allows 40. `docs/wcag-ui.md` XAG 104 row points here.

## Measured

- On a 1920x1080 canvas with `canvas_items` and `expand`, a 1280x800 window scales text by 0.667 but its height by
  0.741, so a subtitle designed at exactly 46 px is 30.67 px against a 34.07 px target there: it warns on a Steam Deck.
- `Test-TextSize.ps1` takes about 33 s with Godot 4.7.2 (four headless runs).

## Not taken, and why

- A subtitle stack class (new lines at the bottom, oldest off the top): a queue of two; a skill rule is enough.
- Preferring line breaks after punctuation: neither talk gives a rule a program could apply; writers break by hand
  instead, and the layout keeps their breaks.
- Direction arrows, presets, subtitle channels, a live preview and VR placement: game- and UI-specific, skill rules only.
- The 8% TV figure (Stevens) and the 160 words-a-minute lower end: 180 is the limit a check needs.

Doubtful transcription: "Amazon's 10-fit UI" (10-foot UI), "Channel 4's sub-targeting guidelines" (probably
subtitling), the name of the Forza speaker mentioned in passing.
