---
name: look
description: Use when the user asks how the game looks, wants its screens critiqued, or is choosing between a visual change and how it was before.
disable-model-invocation: true
---

# /look: style guide, screenshot critique, before and after

Screens are judged against a written style guide, at the resolutions the game targets, from real screenshots. The user makes
the visual calls; you show them evidence and record their choices.

## 1. The style guide (first run only)

`status -Json` returns `look.styleGuide`. If it is null, write `docs/STYLE.md` from `${CLAUDE_PLUGIN_ROOT}/ci/godot/templates/STYLE.md`
with the user, one multiple-choice question per section: target resolutions (design resolution first), palette (offer the
colours the game already uses, read from its themes and scenes), type and smallest text size, readability rules, motion rules.
Keep the `Resolutions:` line on one line; tools read it.

## 2. Critique

Hand the screenshots to the `godot-verifier` subagent so the images stay out of this conversation: every screen the user named
(or the main scenes from `status` `inventory.scenes`), at every resolution in `look.resolutions`:

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/godot-ci.ps1 shot -Json -Quiet -Scene res://ui/Menu.tscn,res://ui/Hud.tscn -Resolution 1920x1080 -Output screenshots/1920x1080
```

Ask it to judge each picture against `docs/STYLE.md` and its "Choices": text too small or clipped, contrast, overlap, things
outside the safe area, colours off the palette, screens that disagree with each other, and the rules in
`godot-ui-accessibility` that a picture can show (colour alone, focus outline, target size, text painted into images).
Name the WCAG criterion with each accessibility problem. Report the problems as a table:
screen | resolution | problem | rule it breaks | screenshot path. Do not fix anything the user has not chosen to fix.

## 3. Before and after

For a visual change, take the "before" pictures first, at the design resolution:

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/godot-ci.ps1 shot -Json -Quiet -Scene res://ui/Hud.tscn -Resolution 1920x1080 -Output screenshots/before
```

Make the change, then compare:

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/godot-ci.ps1 shot -Json -Quiet -Scene res://ui/Hud.tscn -Resolution 1920x1080 -Output screenshots/after -Baseline screenshots/before
```

Each shot gets `compare.changedPercent` and `compare.image`: before | after | changes in red. Look at the comparison image,
then ask one multiple-choice question: **Keep before**, **Take after**, or one or two **named tweaks** you can see would help.
Put the comparison image's path and a one-line description of what changed in the question, so the user can open it. A change
of 0% means the edit did not reach that screen; say so instead of asking.

Revert or keep the change as chosen, and add the decision under "Choices" in `docs/STYLE.md`
(`yyyy-mm-dd, screen: what was chosen and why`), so later critiques respect it.

## 4. Feel

How the game feels in motion is `godot-juice`: offer it when the critique is about responsiveness rather than layout.
