---
name: godot-store-page
description: Use when preparing a Steam, itch.io or Epic store page for a Godot game: capsule art, screenshots, a trailer, the short description, tags, wishlists, Steam Next Fest, the dates between paying for the page and release, or a press kit and review keys for press and streamers.
---

# The store page

A game is bought from its page, and the page is judged in seconds: genre, hook and real gameplay must be obvious at a
glance. Facts here were read from Steamworks' pages and Chris Zukowski's (howtomarketagame.com) on 2026-10-21; sources:
`${CLAUDE_PLUGIN_ROOT}/docs/store-and-legal.md`.

## 1. Steam's images (sizes changed in August 2024; old ones are refused)

| File in `store/steam/` | Size | Notes |
|---|---|---|
| `header_capsule` | 920x430 | top of the page, recommendations |
| `small_capsule` | 462x174 | lists and search: the logo nearly fills it |
| `main_capsule` | 1232x706 | front-page carousel |
| `vertical_capsule` | 748x896 | sale pages |
| `library_capsule` | 600x900 | the library; logo, no other text |
| `library_header` | 920x430 | |
| `library_hero` | 3840x1240 PNG | no text at all; keep the subject in the centre 860x380 |
| `library_logo` | 1280 wide or 720 tall, PNG with transparency | |
| `shortcut_icon` | 256x256 or 512x512 | |
| `app_icon` | 184x184 JPEG | |
| `page_background` | 1438x810 | optional |
| `screenshot1`... | at least 1920x1080, 16:9, at least 5 | gameplay only |

- Keep them in `<project>/store/steam/` with an empty `store/.gdignore` (so Godot does not ship them); `doctor` then
  checks every size, format and the screenshot count.
- Capsules show only the art, the game's name and an official subtitle: no review scores, awards, "Wishlist now" or
  discounts (Valve limits the visibility of capsules that do). Event text goes in an Artwork Override, at most a month,
  translated.
- A professional capsule artist is the most commonly recommended spend (Zukowski: "DO NOT DO YOUR OWN CAPSULE ART").
  A pixel-art game still gets an illustrated capsule, never a screenshot; capsules borrow the genre's visual tropes (a
  hammer for crafting games), so study recent ones in the genre (Zukowski's page makeovers, GDC, about 2021).

## 2. What the page must say in seconds

- **Short description:** the genre, the hook and what the player does, in plain text (no links, no "Out now"); Steam
  allows "a few hundred characters" (300 is the commonly cited limit). `store/steam/short_description.txt` is checked by
  `doctor`. Write verbs, not setting: "Smash bricks, draft upgrades, survive 30 floors" beats "In a war-torn land...".
  When the genre word means different things to different players (roguelike, survival), name the parts the game has
  (permadeath, generated levels, unlocks that persist): 31% of 20XX's negative reviews came from players who did not want
  a roguelike (Christopher King, GDC).
- **Screenshots:** the first four show the core loop (they appear when hovering the game in lists); real gameplay with
  the game's UI, which names the genre at a glance (a reticle, a health bar, a dialogue box), no concept art. Each shows a
  different place, effect or enemy, and one a menu or inventory: a few distinct shots beat many similar ones, which read as
  an asset flip. `shot -Resolution 1920x1080` takes them from real scenes, and `shot -Locale` makes
  translated sets.
- **Trailer:** gameplay in the first seconds, no studio or engine logos first; the first video makes Steam's 6-second
  microtrailer, so it should be gameplay throughout. H.264 and AAC, up to 1920x1080, 30 or 60 fps, 44.1 or 48 kHz audio.
  A release cannot go out while a trailer is still encoding. Capture its footage with the HUD, music and cursor off
  (capture mode and a free camera, `godot-debug-tools`); screenshots keep the UI. Edit it (Derek Lieu, "Trailer Made",
  GDC): open with the hook, and teach early, like a tutorial, the one idea the rest depends on; keep a shot if it is clear,
  interesting, new and pretty, in that order; a logo few people recognise goes on the end slate with the call to action;
  show the cut to someone who has not seen the game.
- **Trailer script:** start from `docs/TRAILER.md`, written in the prototype (template
  `${CLAUDE_PLUGIN_ROOT}/ci/godot/templates/TRAILER.md`, gate `prototype.trailer`): genre in the first 5 seconds, then the
  hook, content (bosses, modes, unlocks) only at the end; and its three standout moments. Without one, write it before
  capturing anything.
- **Accessibility:** a line in the description and the press kit naming the options (colour-blind mode, subtitles,
  remapping), and a page listing them, what is missing included (XAG 121). Hue's press-kit bullet reached the reviews
  that lifted it to a green Metacritic score; Dots and Flow Free had colour-blind options nobody found (Ian Hamilton, GDC).
- **Tags:** at least 5 before launch, up to 20; the first 5 weigh most. Keep "Indie" and praise out of the top 5. List
  the tags of three top games of the genre and keep those all three share that fit yours; a good change shows as a
  Discovery Queue spike in Steam's traffic report. Judge page changes by wishlists per day, with a diary of each change,
  not by click-through (Zukowski, about 2021).
- **Review rubric** (ask someone who has not seen the game, or the `look` skill on the page's screenshots): can they
  name the genre in 5 seconds? The hook? Is the gameplay visible? Is every screenshot readable at thumbnail size? If the
  genre is not clear, the page fails, whatever else is true.

## 3. Dates on Steam

| Step | Rule |
|---|---|
| Steam Direct fee | US$100 per game, recouped after US$1,000 of revenue |
| Fee paid to release | at least 21 days |
| "Coming Soon" page live | at least 2 weeks before release; Zukowski advises months |
| Store page review, build review | 3 to 5 business days each; submit 7 business days ahead; the page before the build |
| Release date | locked 2 weeks before it |
| Release | a manual "Release App" button; approved games do not release themselves |
| Steam Next Fest | once per game; demo review submitted 3 weeks before (5 for the press preview); February 2027: register by January 10, runs February 22 to March 1 |

## 4. Wishlists (Zukowski's data, not rules)

- The old "7,000 wishlists" rule is retired (he archived it in June 2026, after Valve's Personalized Calendar). His
  current tiers at launch: about 5,000 (Bronze), 8,000 (Silver), 50,000 (Gold), 90,000 (Diamond).
- Next Fest (182 games, February 2026): the median gain was 322, 1,006, 5,215 and 12,882 wishlists for games going in
  with under 1,000, 1,000 to 9,999, 10,000 to 99,999 and 100,000 or more; going-in wishlists predict the gain
  (r = 0.825). Do the last Next Fest before launch.
- First-week conversion of 15 to 25% of wishlists is Simon Carless's data from 2020, not Zukowski's.
- Valve: a wishlist from two years before release converts about as well as one from two weeks before.
- Before a seasonal sale, show the game is alive (an event, a small patch, an active forum): in Zukowski's 2020 diary study
  shoppers checked for that, nobody bought at full price, and friends weighed most. Steam sends no reminder before a sale
  ends, so remind followers yourself. A handful of people over three months: a qualitative study, not statistics.

## 5. Other stores

- **itch.io:** cover image 630x500 recommended (315x250 minimum); 3 to 5 screenshots; label adult content and generative
  AI use. Good for prototypes and jams, rarely for revenue.
- **Epic:** logo 960x540 PNG; landscape 2560x1440 and portrait 1200x1600 images; uses IARC age ratings (`godot-legal`).

## 6. Press kit and outreach

From a GDC talk on no-budget marketing (about 2024; `${CLAUDE_PLUGIN_ROOT}/docs/gdc/no-budget-diy-marketing.md`). Its
social-platform advice and wishlist conversion figures are dated and left out: section 4 has current data.

- **Message:** the short description plus a list of bullets of what is unique (mechanics, art style, music and composer,
  length, modes, player count), reused on the store page, in the press kit and in every email. Shapes that work:
  `<verb> a <noun> while you <verb>`; `<Name> is a <genre> where you <verb> and <verb>`; a line of story ending in a
  question to the player. Name the genre rather than lean on "like <other game>".
- **Press kit in `store/press/`** (`doctor` warns about gaps): `key_art` and `key_art_notitle` (press ask for both),
  6 to 10 `screenshot*`, and `fact_sheet.txt` or `press_release.txt` with the short description, bullets, platforms,
  date, trailer and store links and a contact email (a separate press@ address: it becomes public). Publish it on the
  game's site so nobody who wants to cover the game lacks the material.
- **Press list:** name, email, handle, outlet or streaming platform, platforms they play on, region (send in their
  daytime), notes. Only contact details they list publicly; include small streamers and niche sites, not only big
  outlets.
- **When to write:** the announcement (trailer, screenshots), the release window, a new demo or a major festival only,
  then the release date, announced no more than a few months ahead.
- **Keys:** review keys about a month before release, with an embargo date and time. The launch-day email is short:
  a subject naming the genre and saying it releases today, the short description, bullets, store, press kit and press
  release links, a small GIF and a key, so nobody has to ask. Do not give keys to everyone who asks.
