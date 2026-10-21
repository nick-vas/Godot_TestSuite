---
name: godot-legal
description: Use when a Godot game is being prepared for release or sale and needs age ratings, a privacy policy, an end-user licence, loot box or in-game purchase decisions, a check of the rights to its music, art, fonts and code, or a review of a publishing agreement before signing.
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

## 6. Publisher agreements: what to check before signing

From a London games lawyer's GDC talk (Tim Rippon-Davies, about 2021): common-law (English or US-style) contracts,
general information, **not legal advice**; notes in `${CLAUDE_PLUGIN_ROOT}/docs/gdc/contract-killers.md`. The numbers
are his norms and examples, not legal limits. The publisher's draft protects the publisher: expect to negotiate to a
compromise, and treat a publisher that will change nothing as a warning sign. A lawyer reads the final draft.

- **Licence, not assignment.** An exclusive licence for a term is the usual grant. An assignment, even of 1%, gives the
  publisher leverage: it needs the rights to revert at the end of the term and on the publisher's breach. Either way,
  carve out your own tools, tech and code libraries; the publisher gets a non-exclusive licence to them.
- **Term:** 5 to 10 years is usual; 25 years or perpetuity is a red flag. Check what it counts from: "five years from
  the last version released" restarts with every DLC, port or new version the definition of the game includes.
- **Auto-renewal:** know the renewal period and the notice deadline that stops it. Renewal while revenue stays above a
  threshold is fair only if the threshold is not tiny (his too-low example: EUR 10,000, once the publisher's cut is taken).
- **Territories and platforms:** grant only where the publisher has a plan (ask how and through whom). Write down what
  you must deliver ("PC" may mean Windows only). For unfunded platforms, sequels, prequels and spin-offs, give a first
  option or right of first refusal with a time limit on negotiating, ending with the term, instead of the rights. Ports
  the publisher makes carry the same quality promises you give.
- **What else the grant takes:** non-competes limited in time and scope ("no game in the same genre" is too broad);
  merchandise, soundtrack and film or TV rights only if the publisher will use them, and never across deals already
  signed (a composer selling the soundtrack).
- **Milestones:** the publisher reviews within a fixed time (normally 10 working days); no answer in time means approved
  for payment; a rejection comes with reasonably detailed feedback; changes to the agreed spec need your approval and
  more money.
- **Cash flow:** the payment term (30 days from approval is common) comes on top of the review window, so about 44 days
  from delivery, more after each rejection. "45 days from the end of the month" pays revenue from the 1st about 75 days
  later; a statement that must come first can add more.
- **Back end:** the share counts all money the game earns (exclusivity and subscription deals, in-game purchases, ads,
  merchandise, film or TV). Deductions are a closed list with evidence; recoupable marketing is third-party costs with
  invoices; internal costs are queried. Statements monthly or quarterly, by platform and territory; an audit right.
- **Recoup source:** the common model recoups advances and costs from gross receipts, then splits. Recouping only from
  the developer's share is the one to refuse (example below).
- **Delays and termination:** delays by the publisher, or by third parties it makes you use, extend your dates day for
  day. A missed milestone gets a cure period (look in the termination section). Strike "time is of the essence" for
  milestones: it allows termination for any lateness, cure period or not; if it stays, deliver something on each date.

Worked example (illustrative numbers, not the talk's): the publisher's advances and recoupable costs C = 100,000; the
developer's share s = 50% of receipts R after the store's cut; neither column goes below 0.

| Receipts R | Developer, recoup from gross: s(R - C) | Developer, recoup from its share: sR - C |
|---:|---:|---:|
| 100,000 | 0 | 0 |
| 200,000 | 50,000 | 0 |
| 300,000 | 100,000 | 50,000 |
| 500,000 | 200,000 | 150,000 |

Recouping from the developer's share makes the developer repay all of C alone: the first payment comes at R = C/s
instead of R = C, and from then on its total is (1 - s)C lower for good.
