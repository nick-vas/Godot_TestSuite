# Publisher agreements: what to check before signing

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
