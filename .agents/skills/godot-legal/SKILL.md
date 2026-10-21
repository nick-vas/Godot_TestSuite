---
name: godot-legal
description: Use when a Godot game is being prepared for release or sale and needs age ratings, a privacy policy, an end-user licence, loot box or in-game purchase decisions, or a check of the rights to its music, art, fonts and code.
---

# Legal basics for releasing a game

General information for developers, read from the stores' and regulators' own pages on 2026-10-21; **not legal advice**.
For anything with money or children involved, or when unsure, ask a lawyer. Never invent a requirement: say what the
source says, and say when it is unconfirmed. Sources: `${CLAUDE_PLUGIN_ROOT}/docs/store-and-legal.md`.

## 1. Age ratings

- **IARC:** one free questionnaire inside a store's portal gives ratings for many regions at once (ESRB, PEGI, USK,
  ClassInd, ACB, GRAC, IGRS and others). Used by Google Play (required: apps without a rating are removed), Microsoft,
  Nintendo, PlayStation, Epic, Meta and others. **Steam is not an IARC store.**
- **Steam:** the Content Survey (general content, mature content, generative AI use) must be done before review; it
  produces Valve's own ratings, which Germany (since 15 November 2024) and Indonesia require. Never enter on Steam a USK
  rating that came from IARC on another store (Valve forbids it).
- **What raises a rating** (PEGI, since June 2026): paid random items make a game PEGI 16 (18 for social casino);
  time-limited offers PEGI 12; daily rewards PEGI 7 (12 if missing them is punished); chat without block, mute and
  moderation PEGI 18; simulated casino gambling PEGI 18. ESRB adds "In-Game Purchases (Includes Random Items)", "Users
  Interact" and "Shares Location" notices.
- Answer the questionnaire from what is in the build, all of it, including content players cannot reach.

## 2. Privacy policy

- **Required** by Google Play for every app, even one that collects nothing, and by the App Store for every app, with a
  link in the store listing and in the game. Steam's public pages were not found to require one, but the law does whenever
  the game itself handles personal data (analytics, crash reports, accounts, online play).
- What it must say (GDPR Art. 13): who you are and how to reach you; what data, for what purposes, on what legal basis;
  who receives it; transfers outside the EU; how long it is kept; the player's rights (access, deletion, objection,
  withdrawing consent); the right to complain to a regulator.
- Children: under GDPR a child's own consent counts from 16 (member states may lower it to 13); below that, a parent's.
  The US COPPA rule applies to services for children under 13.
- The kit's telemetry model (`godot-telemetry`) is built for this: nothing sent before consent, per purpose, no free
  text, export and erase. The policy describes exactly that schema, and its version matches `policyVersion` in the code.
- Store forms (Google Play's Data safety, Apple's privacy details) must match the policy, including what third-party SDKs
  collect.

## 3. End-user licence

- On Steam, the Steam Subscriber Agreement licenses the game to the player when the game has no licence of its own; a
  game can add its own (configured with Valve).
- An own licence usually covers: the licence grant and its limits, ownership, forbidden uses (cheating, reverse
  engineering), conduct online, **who owns mods and player content** and what licence the developer gets to it
  (`godot-modding`), termination, warranty and liability limits. Consumer law limits what it can exclude.

## 4. Rights to everything in the game

- Every asset, font, sound, music track, shader and code library has a source and a licence in `assets.json`
  (`godot-asset-pipeline`); `doctor` warns about files no entry covers.
- Not in a game that is sold: non-commercial licences (CC BY-NC). GPL-family code may require publishing the game's code;
  read it before use. No-derivatives licences (CC BY-ND) forbid changing the work.
- Bought asset packs carry the vendor's licence: record it as `LicenseRef-<vendor>` and keep the receipt and terms.
- Music: a licence for the game is not always a licence for trailers or streams; check both.
- CC BY 3.0 and 4.0 forbid technical measures that restrict what the licence allows; whether a store's DRM wrapper is
  one is unsettled (OGA-BY was written to avoid the question). Prefer CC0 or OGA-BY assets for a DRM build, or ask.
- Fonts under the OFL may be shipped and sold with the game, never sold on their own; a modified font loses its Reserved
  Font Name.
- Credits and notices are generated, not typed: `godot-credits`.

## 5. Before launch

- [ ] IARC done for every IARC store; Steam's Content Survey done; answers match the build
- [ ] privacy policy published (always, for Android and iOS) and linked from the game and the store
- [ ] `assets.json` covers every file; `credits` passes
- [ ] an end-user licence decided (own or the store's) and a mod/player-content clause if the game has either
- [ ] refunds understood (Steam: within 14 days and under 2 hours of play)
