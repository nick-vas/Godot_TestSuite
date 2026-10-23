---
name: godot-legal
description: Use when a Godot game is being prepared for release or sale and needs age ratings, a privacy policy, an end-user licence, loot box or in-game purchase decisions, a check of the rights to its music, art, fonts and code, a review of a publishing agreement before signing, or agreements with collaborators or clients.
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

From a London games lawyer's GDC talk (Tim Rippon-Davies, about 2021; common-law contracts); notes in
`${CLAUDE_PLUGIN_ROOT}/docs/gdc/contract-killers.md`. The numbers are his norms, not legal limits. The draft protects the
publisher: negotiate to a compromise; a publisher that will change nothing is a warning sign. A lawyer reads the final.

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
  merchandise, film or TV); a share of gross is more of net (20% of gross is 29% of net after a 30% store cut).
  Deductions are a closed list with evidence; recoupable marketing is third-party costs with invoices; internal costs
  are queried. Statements monthly or quarterly, by platform and territory; an audit right.
- **Recoup source:** the common model recoups advances and costs from gross receipts, then splits. Recouping only from
  the developer's share is the one to refuse (example below).
- **Delays and termination:** delays by the publisher, or by third parties it makes you use, extend your dates day for
  day. A missed milestone gets a cure period (look in the termination section). Strike "time is of the essence" for
  milestones: it allows termination for any lateness, cure period or not; if it stays, deliver something on each date.

A developer's red flags, from Jan Willem Nijman's comments on a 2020 publisher draft (his opinions; with Whitethorn's
2020 sample agreement, clause by clause in `${CLAUDE_PLUGIN_ROOT}/docs/publisher-contracts.md`). Read each clause as
what the publisher could do with it; ask for a number, list or date wherever it says "sole discretion", "fair market
value" or "not unreasonably withheld".

- **Markup and split:** no markup on the advance; a split that depends on the advance (his 2020 benchmark: 70/30 to the
  developer after recoup, for advances up to about $100k); the advance must also cover the months after launch before
  store payments arrive.
- **One-sided exits:** ending the deal for convenience costs the publisher notice, a payment and the rights, with no
  claim on the game's later revenue; a breach never hands over the game or demands repayment at once; the rights revert
  when the publisher stops selling the game.
- **Hidden costs:** no return reserves from your share; no cut of sequels it does not publish; marketing plan, budget
  and services in writing, per item; support, bug-fix and travel duties with limits; no ban on criticising it; audit
  rights over its statements for you, not over your spending for it.

Recouping from the developer's share makes the developer repay all of the publisher's advances and costs C alone. With
a share s of receipts R: s(R - C) recouping from gross, sR - C from the share (neither below 0). The first payment comes
at R = C/s instead of R = C, and the total stays (1 - s)C lower for good (worked numbers in the talk's notes).

## 7. United States: the CVAA, when players can talk to each other

A game with text, voice or video chat between players falls under the US CVAA (47 CFR Part 14): the chat and the path to
it (menus, matchmaking, friends lists) must be accessible unless not achievable; records of how disabled players were
consulted are kept until two years after the game stops being offered; an officer certifies them every 1 April. Read
[cvaa.md](cvaa.md) before shipping chat to the US.

