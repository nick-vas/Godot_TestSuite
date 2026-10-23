---
name: godot-legal
description: Use when a Godot game needs age ratings, a privacy policy, an end-user licence, loot box or purchase decisions, a check of its rights to music, art, fonts or code, or a publishing, collaborator or client agreement reviewed.
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
- **Paid random items:** build them, and trading items between players, behind per-country switches kept in data, so one
  country's rule removes a feature rather than the whole game (Will Bucher, GDC 2019; that talk's country rules are dated).
  The App Store requires each item type's odds shown before purchase (App Review Guideline 3.1.1, read 2026-10-22). Do
  not quietly tune odds inside a shown type to keep players buying: the talk saw a fraud risk. Offer parental controls.

## 2. Privacy policy

- **Required** by Google Play for every app, even one that collects nothing, and by the App Store for every app, with a
  link in the store listing and in the game. Steam's public pages were not found to require one, but the law does whenever
  the game itself handles personal data (analytics, crash reports, accounts, online play).
- What it must say (GDPR Art. 13): who you are and how to reach you; what data, for what purposes, on what legal basis;
  who receives it; transfers outside the EU; how long it is kept; the player's rights (access, deletion, objection,
  withdrawing consent); the right to complain to a regulator.
- Children: under GDPR a child's own consent counts from 16 (member states may lower it to 13); below that, a parent's.
  US COPPA covers services for children under 13 and games that appeal to them in a major way. A lawyer's GDC talk
  (Chris Reed, about 2016): a neutral age gate asking the birth date, never "are you under 13?", sending younger players
  to a version that collects nothing; COPPA safe-harbor companies help.
- The kit's telemetry model (`godot-telemetry`) is built for this: nothing sent before consent, per purpose, no free
  text, export and erase. The policy describes exactly that schema, and its version matches `policyVersion` in the code.
  Keep it in `store/privacy-policy.md` saying "Version N": `doctor` warns when telemetry or a phone preset has no policy,
  or the policy is not at the code's version.
  Never copy another game's policy: it describes someone else's practices, so it misleads players (Reed). Link it from the
  main menu or splash screen and from the website's footer.
- Store forms (Google Play's Data safety, Apple's privacy details) must match the policy, including what third-party SDKs
  collect.

## 3. End-user licence

- On Steam, the Steam Subscriber Agreement licenses the game when it has no licence of its own (Valve can add one).
- An own licence usually covers: the licence grant and its limits, ownership, forbidden uses (cheating, reverse
  engineering), conduct online, **who owns mods and player content** and what licence the developer gets to it
  (`godot-modding`), termination, warranty and liability limits. Consumer law limits what it can exclude.

## 4. Rights to everything in the game

- Every asset, font, sound, music track, shader and code library has a source and a licence in `assets.json`
  (`godot-asset-pipeline`); `doctor` warns about files no entry covers.
- Not in a game that is sold: non-commercial licences (CC BY-NC). GPL-family code may require publishing the game's code;
  read it before use. No-derivatives licences (CC BY-ND) forbid changing the work.
- Bought asset packs carry the vendor's licence: record it as `LicenseRef-<vendor>` and keep the receipt and terms.
- Music: a licence for the game is not always a licence for trailers, streams or a soundtrack release; check each.
- CC BY 3.0 and 4.0 forbid technical measures that restrict what the licence allows; whether a store's DRM wrapper is
  one is unsettled (OGA-BY was written to avoid the question). Prefer CC0 or OGA-BY assets for a DRM build, or ask.
- Fonts under the OFL may be shipped and sold with the game, never sold on their own; a modified font loses its Reserved
  Font Name.
- Credits and notices are generated: `godot-asset-pipeline`.

**Work made by anyone else, owners included.** From a lawyer's GDC talk (Chris Reed, about 2017; US law).

- Whoever makes a work owns its copyright: the artist the art, the sound designer the sound, the programmer the code. The
  studio owns it only through a written, signed agreement: work for hire for contractors, an invention (IP) assignment for
  the studio's owners and co-founders. An email, or a handshake, does not transfer copyright.
- The agreement makes the work a work for hire and, in case a court disagrees, assigns it anyway. A maker's portfolio use
  is a licence the studio controls: what may be shown, and nothing before launch.
- Sign before work starts. Fixing it afterwards is possible but depends on a former contributor's goodwill; even an unused
  first round can come back as a claim that the game is derived from it.
- The risk is concrete: his clients had games pulled from Steam by a former contractor's DMCA notice. Publishing deals
  make the studio promise the game infringes no one's rights, which is only true when every contributor has signed.
- When the maker keeps ownership and grants a licence instead, the game may use the work only as far as the licence says.
- In `assets.json` such work is `"source": "commissioned"`, with `agreement` (a reference, never the contract itself),
  `rights` (`assigned` or `licensed`) and, for a licence, `uses`. `doctor` warns when any is missing.
- Calling someone a contractor in the contract does not make them one for tax: ask an accountant.

**The game's name, registration and the company.** From his GDC talks of about 2016 and 2018 (US law; fees are from
then).

- Search the name before a logo or store page (the web, Steam, the trademark databases where it will sell: USPTO in the
  US, EUIPO in the EU). For trademarks every video game is the same kind of product, so a game of any genre with the same
  or a similar name conflicts (plan gate `concept.name`).
- US trademark rights come from selling the game (a domain, social accounts, a Kickstarter or press give none; Early
  Access is unclear). An intent-to-use application holds the date for up to three years. With money for one filing,
  register the name as a word mark (about US$1,500 with an attorney in 2018).
- Copyright needs no registration, but a US registration (about US$65 then) within three months of launch gives the most
  coverage; include about 30 seconds of gameplay video so a judge can see the game.
- Mechanics and ideas are not protected: pitch a prototype under an NDA; dated design docs and git history show what
  you made when. Fair use is an argument in court, not a safe harbour. No real person's name or likeness without
  permission, and no former employer's secrets from a new hire.
- A company (in the US often an LLC) once the project gets serious, before working with others, with a written operating
  agreement even for one owner: without the formalities its liability protection can be challenged.

**Other agreements to have in writing** (a checklist, not templates; a lawyer drafts them):

- [ ] An unpaid or student team: who owns what each member made, what happens when someone leaves, credit, and any
  revenue split, signed before work starts. If each member keeps their own assets, the game needs every member's
  consent to ship.
- [ ] The studio as the contractor (a port, co-development, a client's game): the studio keeps its own tools and code;
  acceptance criteria per milestone, payment on acceptance, a kill fee, portfolio rights.
- [ ] Releasing the game's own source: its licence chosen, and every asset's licence allows it.
- [ ] Tabletop rules text: mechanics are free, the words are not. SRD 5.1 is offered under CC BY 4.0 or OGL 1.0a, SRD
  5.2 under CC BY 4.0 only (Wizards of the Coast's SRD page, read 2026-10-22): ship the attribution the licence asks for
  and use only what the SRD contains.
- [ ] Parody or homage: the owner of a name, look or asset agrees first, and their assets are used on their terms
  (Google asked Nintendo, and Square Enix supplied its Dragon Quest art, for 8-bit Maps; *Untold History*).

## 5. Before launch

- [ ] IARC done for every IARC store; Steam's Content Survey done; answers match the build
- [ ] privacy policy published (always, for Android and iOS) and linked from the game and the store
- [ ] `assets.json` covers every file; `credits` passes
- [ ] everyone who made something for the game, owners included, signed an assignment or licence
- [ ] an end-user licence decided (own or the store's) and a mod/player-content clause if the game has either
- [ ] refunds understood (Steam: within 14 days, under 2 hours played)
- [ ] chat between players, sold in the US: CVAA records kept and the yearly certificate filed (section 7)

## 6. Publisher agreements: what to check before signing

Before anyone signs a publishing deal, read [publishers.md](publishers.md) and go through the draft clause by clause:
licence rather than assignment, term and renewal, territories and platforms, milestones and payment timing, the back end
and what is recouped from it, delays and termination, and a developer's red flags. Its numbers are one lawyer's and one
developer's norms, not legal limits; a lawyer reads the final draft.

## 7. United States: the CVAA, when players can talk to each other

A game with text, voice or video chat between players falls under the US CVAA (47 CFR Part 14): the chat and the path to
it (menus, matchmaking, friends lists) must be accessible unless not achievable; records of how disabled players were
consulted are kept until two years after the game stops being offered; an officer certifies them every 1 April. Read
[cvaa.md](cvaa.md) before shipping chat to the US.

