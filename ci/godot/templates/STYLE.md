# {{GAME}}: style guide

<!-- Written once with the user by /look, then the reference for every screenshot critique. The "Resolutions:" line is read
     by tools: keep it on one line, comma-separated, the design resolution first. -->

Resolutions: 1920x1080, 1280x720, 3840x2160

## Palette

| Role | Colour | On Background | Use |
|---|---|---|---|
| Background | #1E1E24 | | |
| Text | #F2F2F2 | 14.8:1 | |
| Accent | #FF8A5B | 7.1:1 | the one thing to look at |
| Danger | #F2555A | 4.9:1 | damage, warnings |

Every text colour is at least 4.5:1 on the backgrounds it is used on (WCAG 1.4.3). Work the ratio out with WCAG's
formula (`godot-ui-accessibility`); do not judge it by eye.

## Type

Font family and weights, with a sans-serif option. Smallest text at 1080p, measured as body height (ascender to
descender): 18 px on PC, 26 px on console and TV (XAG 101); a UI scale setting up to 200%. HUD numbers 32 px or more.

## Readability

- Text contrast at least 4.5:1 against what is behind it, after the post-process grade; 3:1 only for large text (36 px on PC, 52 px on console, at 1080p: XAG 102),
  and for focus rings, slider tracks, checkboxes and HUD icons (WCAG 1.4.3, 1.4.11).
- Nothing is told by colour alone: states and teams also get an icon, shape or word (1.4.1).
- Everything important inside the central 90% of the screen (safe area).
- No text or button overlaps another at any listed resolution, or at 200% UI scale (1.4.4).
- Clickable controls at least 24 x 24 px at 1080p; the focused control always has a visible outline (2.5.8, 2.4.7).

## Motion

- Feedback starts within 100 ms of the action (juice.json checks it).
- UI transitions 150 to 250 ms, ease out; nothing bounces more than once.
- Screen shake and flashes can be reduced in the settings; never more than three flashes a second over about 20% of the screen
  (WCAG 2.3.1, XAG 118).

## Choices

Decisions made with /look, newest first, so later critiques respect them:

- yyyy-mm-dd, screen: what was chosen and why.
