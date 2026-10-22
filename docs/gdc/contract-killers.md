# Contract Killers: What Developers Should Eliminate From Their Publishing Agreement

- Speaker: Tim Rippon-Davies, games lawyer and partner at Sheridans, London. Whisper writes "Tim Ripper-Davies"; the
  spelling here is a reconstruction, not confirmed from the video.
- Year: not stated. About 2020-2021 by its references: he is a trustee of Safe in Our World (founded 2019), names Epic Games
  Store and Xbox Game Pass deals as revenue sources, and points to his articles "on Gamasutra", which was renamed Game
  Developer in 2021. The skill says "about 2021".
- Video: https://www.youtube.com/watch?v=yfrwQnqwPps
- Topic doc: [store-and-legal.md](../store-and-legal.md); skill: `.agents/skills/godot-legal/SKILL.md` section 6.
- Jurisdiction: a London lawyer's view; the talk names no governing law. Material breach, cure periods and "time is of the
  essence" are English and US common-law ideas. He says the talk is legal education, not legal advice; so is the kit's
  summary.

## What the talk says

- A publisher's draft protects the publisher, even where the developer is not at fault. Expect a compromise, not a
  symmetrical contract; a publisher that will negotiate nothing is a partner to reconsider. Larger publishers (and larger
  budgets) bend less; a first game is a higher risk and gets worse terms; a late-stage project gets better ones.
- IP: an exclusive licence for a term is better than an assignment. Co-ownership is messy, and even 1% gives the
  publisher power. Any assignment needs reversion at the end of the term and on the publisher's breach, and a carve-out of
  the developer's tools, tech and code libraries, licensed back non-exclusively.
- Term: usually 5 to 10 years; 25 years or perpetuity is too long. Five years "from the last version" restarts with each
  DLC, add-on or port the definition of the game covers. Auto-renewal can run on silently (know the notice deadline), or
  while revenue stays above a threshold; EUR 10,000 is his example of one set too low.
- Territory, platforms, scope: ask how and through whom the publisher covers each region, and keep regions it will not
  serve (his example: China). Say which platforms you deliver ("PC" may need to mean Windows only). Unfunded platforms,
  sequels and spin-offs: a first option or right of first refusal, time-limited and ending with the term, not the rights.
  Third-party ports should carry quality warranties. Limit non-competes (same genre is too broad) and merchandise,
  soundtrack, film and TV rights, especially where a composer already has soundtrack rights.
- Front-end payments: a review deadline (normally 10 working days), deemed approval for payment if it passes, detailed
  reasons for a rejection, no spec change without approval and pay. Payment 30 days after approval adds to the review time.
- Back end: count all revenue (exclusivity deals, Game Pass, in-game purchases, ads, merchandise, film and TV); a closed
  list of deductions with evidence; recoupable marketing limited to third-party costs with invoices; an audit right
  (customary); statements monthly or quarterly, by platform and territory. "45 days from the end of the month" means
  revenue from the 1st arrives about 75 days later.
- Recoupment: the common model recovers costs 100% from gross, then splits. Recovering costs and advances from the
  developer's share only is "grossly unfair": the publisher profits from day one and the developer waits far longer.
- Timing: publisher delays (and those of third parties it imposes, such as porting houses) extend the developer's dates
  day for day; a missed milestone needs a cure period; "time is of the essence" for milestones allows termination for
  any lateness regardless of cure periods, so strike it, or deliver something on every date.

## What the kit took

- `.agents/skills/godot-legal/SKILL.md`: section 6, a checklist of the clauses above with his numbers, marked general
  information, not legal advice; a worked example (illustrative numbers, not his) of recoup from gross against recoup
  from the developer's share; the description now names a publishing agreement review as a trigger.
- `evals/review-publishing-deal/`: a term sheet with three planted clauses (term from the last version, recoup from the
  developer's share, time of the essence) among fair ones; graders check that all three are flagged, that fair clauses are
  not attacked, and (with the plugin only) that `godot-legal` was used.
- `docs/store-and-legal.md`: the source row.

## Not taken, and why

- A C# helper in `Breakout.Core` for the payout. The arithmetic is two lines (s(R - C) against sR - C), Breakout's core is
  not shipped to games, and nothing in a game would call it; a table in the skill reaches the agent that needs it.
- A `plan` or `doctor` check: contracts are not in the game's files.

## Numbers and checks

- Worked example (C = 100,000, s = 50%): at receipts of 200,000 the developer gets 50,000 recouping from gross and 0 from
  its own share; at 500,000, 200,000 against 150,000. The gap is (1 - s)C once both pay.
- The eval case was not run (`claude plugin eval` calls the model and costs money). Its schema was checked by the eval
  loader with no run started; see the commit message.
