# Practical Contract Law 201 for Indie Developers: Moderately Scary Edition

- Speaker: Chris Reed, founder of Chris Reed Law (as transcribed; the transcript spells it "Reed" both times, matching the
  firm's name, but the spelling comes from Whisper).
- Year: not stated. GDC 2017 is implied: his 101 talk was the year before, and he calls the $500 million verdict against
  Oculus (February 2017) recent.
- Video: https://www.youtube.com/watch?v=t8UFJ3obm-Q
- Topic doc: [store-and-legal.md](../store-and-legal.md); skill: `.agents/skills/godot-legal/SKILL.md` section 4.
- US law, general information. The speaker says he is not the audience's lawyer, and nothing here is legal advice.

## What the talk says

- Contracts give a relationship predictable rules for the bad case and for unexpected success. Some things need a signed
  writing to happen at all, above all a transfer of copyright: an email will not do it.
- Don't stitch a "Franken contract" together from clauses found online; it is code nobody has read. Contracts do not
  enforce themselves: act on a breach at once (notice, stop working, keep the code until the last payment).
- NDAs are the only way to protect ideas and mechanics, which copyright does not cover. Define what is confidential, what
  it may be used for, for how long and who may be told.
- Work-for-hire agreements, between the studio and anyone who contributes, owners included (who sign an invention
  assignment). The maker owns what they make by default. The agreement makes the studio the owner and, as a fallback if a
  court disagrees, assigns the rights. Portfolio use is a controlled licence, never before launch. He has had clients whose
  games were pulled from Steam by a DMCA notice from a former contractor with a bad or missing contract.
- Revenue share must say a share of what (net of Steam's cut? of a publisher's?), whether it vests, which platforms and
  which products (sequels, DLC). A statement of work lists the deliverables; the developer can terminate, with defined
  pay. The contractor promises the work infringes nothing, because the studio will make the same promise to a publisher.
- Development agreements (a client pays the studio): assign the game only on the final payment; keep your engine, tools
  and libraries and license them; about 50% up front, then milestones; a build counts as accepted if the client is silent
  for about five days; change orders against scope creep; a kill fee when the client cancels for convenience.
- Publishing agreements: a licence, not an assignment; check its length, territory, platforms and products (even future
  unrelated games). He does not accept 30/70 as a standard. Recoupable advances and marketing make the split 100/0 until
  repaid. The publisher's obligations must be specific; get out on 30 days' notice, or a short term, or a revenue floor.
- EULAs: a licence, not a sale; conduct rules; who owns player content (with a licence back); virtual items are not
  property; liability limits. Players must accept again on every update, and the record should show it.
- Q&A: anyone can make a claim, even after an unused first round of work, so sign before work starts. Calling someone an
  independent contractor in a contract does not make someone one for tax.

## What the kit took

- `ci/godot/lib/Assets.ps1`: `"source": "commissioned"` in `assets.json` with `agreement` (a reference to the signed
  document), `rights` (`assigned` or `licensed`) and, for a licence, `uses`. Backward compatible: other entries unchanged.
- `ci/godot/lib/Doctor.ps1`: WARN for a commissioned entry with no agreement, with rights neither assigned nor licensed, or
  licensed with no uses; INFO listing licensed entries with their uses.
- `ci/godot/lib/Credits.ps1`: commissioned work is the game's own (no third-party credit, no "bought asset" warning)
  unless its licence asks for a credit, which then needs no source URL.
- Tests: `tests/Test-AssetManifest.ps1` on five commissioned entries in `tests/assets-fixture` (the four new checks fail on
  the old code); `tests/Test-Credits.ps1` on two in `tests/credits-fixture` (four checks fail on the old code).
- `.agents/skills/godot-legal/SKILL.md` section 4 (the rules, marked US and not legal advice) and a release checklist line;
  one line in `.agents/skills/godot-asset-pipeline/SKILL.md`; the fields in `docs/reference.md`.

## Not taken

- A warning when licensed music leaves out trailers: the talk does not discuss music or trailer licences. The kit's older
  line ("a licence for the game is not always a licence for trailers or streams") comes from elsewhere; `doctor` lists
  each licence's uses instead.
- Revenue share, development, publishing, NDA and EULA terms: contract wording the kit cannot check. Re-accepting the EULA
  on each update could follow the telemetry consent's `policyVersion`; left for a change of its own.
- A plan gate for signed assignments: `doctor` already reports it where the assets are listed.
