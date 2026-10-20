# {{GAME}}: style guide

<!-- Written once with the user by /look, then the reference for every screenshot critique. The "Resolutions:" line is read
     by tools: keep it on one line, comma-separated, the design resolution first. -->

Resolutions: 1920x1080, 1280x720, 3840x2160

## Palette

| Role | Colour | Use |
|---|---|---|
| Background | #1E1E24 | |
| Text | #F2F2F2 | |
| Accent | #FF8A5B | the one thing to look at |
| Danger | #E5484D | damage, warnings |

## Type

Font family and weights. Smallest text: 24 px at 1080p (scales with the window); HUD numbers 32 px or more.

## Readability

- Text contrast at least 4.5:1 against what is behind it, after the post-process grade.
- Everything important inside the central 90% of the screen (safe area).
- No text or button overlaps another at any listed resolution.

## Motion

- Feedback starts within 100 ms of the action (juice.json checks it).
- UI transitions 150 to 250 ms, ease out; nothing bounces more than once.
- Screen shake and flashes can be reduced in the settings.

## Choices

Decisions made with /look, newest first, so later critiques respect them:

- yyyy-mm-dd, screen: what was chosen and why.
