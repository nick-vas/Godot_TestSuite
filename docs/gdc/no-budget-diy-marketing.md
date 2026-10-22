# No Budget DIY Marketing for Indie Games

- Speaker: Michelle, senior producer at Armor Games Studios, before that marketing at another indie publisher (Cozy
  Grove, Sail Forth). Her surname is not in the transcript.
- Year: not stated. About 2024 (inferred): her example trailer end slate announces a third-quarter 2024 release, she
  says TikTok may soon be banned in the US, and that Twitter has declined over the past two years.
- Video: https://www.youtube.com/watch?v=NWyZlGMysH8
- Topic doc: [store-and-legal.md](../store-and-legal.md); skill: `.agents/skills/godot-store-page/SKILL.md` section 6.

## Lessons

- The message comes first: one short line aimed at a defined audience, saying what kind of game it is and what the
  player does. Her templates (one slide): `<verb> a <noun> while you <verb>`, `<Name> is a <genre> where you <verb> and
  <verb>`, or a line of story followed by an in-world call to action. Lean on the genre, not on comparisons with other
  games.
- Add a list of bullet points of what is unique (mechanics, art style, soundtrack and a well-known composer, modes,
  length). The same line and bullets go on the store page, in the press kit and in every email to press.
- Set up a website hub and a press kit early: press who want to cover a game but cannot find its material will not.
- Keep a press list as a spreadsheet: name, email, handle, outlet or streaming platform, platforms they play on, region
  (to send in their daytime), notes. Use only contact details people list publicly; include small streamers and niche
  sites, found through Twitch tags or reviewers of similar games.
- Write to press at the beats that matter: announcement, release window, a new demo or a big festival (not every small
  one), the release date (announced no more than a few months ahead), and launch.
- Send review keys about a month before release, with an embargo. On launch day send a short email: the line, the
  bullets, store page, press kit and press release links, a small GIF or screenshot, and a key. In her words: "You don't
  want to create an extra step by making the press and influencers have to ask you for a key."
- With a press release: 6 to 10 screenshots and key art both with and without the title, which press often ask for; a
  contact address, ideally a separate press@ one since it becomes public.
- Hand keys out with care: giving them to everyone who asks devalues the game.
- Also in the talk: a five-hour-a-week plan (social posts, press list, networking and festivals, devlog and store page,
  capturing content), community building, word of mouth, measuring success by goals that matter to you.

## What the kit took

- `.agents/skills/godot-store-page/SKILL.md` section 6: the message shapes, the press kit contents, the press list
  columns and public-contacts-only rule, when to write, review keys with an embargo and the launch email.
- `ci/godot/lib/Store.ps1` `Test-PressKit` and `ci/godot/lib/Doctor.ps1`: when a project has `store/press/`, `doctor`
  warns about missing `key_art` or `key_art_notitle`, a screenshot count outside 6 to 10, and a missing fact sheet or
  press release, or one with no contact email. Warnings only: a game can ship without a press kit.
- `.agents/skills/godot-release-readiness/SKILL.md`: one checklist line (press kit passes `doctor`, review keys sent
  with an embargo).
- `tests/Test-Store.ps1`: a complete kit passes; 11 screenshots, a kit with only key art with the title, 4 screenshots
  and a press release without an email, and a kit with no text file are each named; `doctor` warns (never fails) on a
  project with the thin kit. The doctor assertions fail without the `Doctor.ps1` change, and the whole test stops
  without `Test-PressKit`.

## Not taken, and why

- Platform advice (Twitter, TikTok, Reddit, Instagram, Discord) and the claim that wishlists convert 10 to 30% in the
  first year: dated; the skill's section 4 has current wishlist data. The two-week launch discount lock is likewise not
  repeated (the skill already has Steam's current date rules).
- The weekly schedule and community advice: about the developer's time, nothing a kit check or a game file can hold.
- A plan gate (`launch.press`): the release-readiness checklist line covers it without changing every game's plan.
- Image size checks for the press kit: the talk gives no sizes, and outlets differ.
- The view that paid promoted posts rarely pay back (Q&A): her opinion, citing research she did not name.

## Numbers

- 6 to 10 screenshots and both key art versions (her press release list); review keys about a month before release;
  release date announced no more than a few months ahead. No measurements were made here.
