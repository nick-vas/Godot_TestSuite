# Publisher contracts: two public sample agreements

Two publishing agreements from 2020 that were shared openly so developers could learn from them, read clause by clause.
Neither is legal advice, and neither is a statement about either publisher's contracts today. They complement the
lawyer's view in `godot-legal` section 6 ([gdc/contract-killers.md](gdc/contract-killers.md)).

- **Raw Fury, "Raw Fury Loves Publishing Your Games"** (the file's title, a draft dated 2020-11-09): Jan Willem Nijman
  (co-founder of Vlambeer) annotated it with 53 comments on 2020-12-22. One experienced developer's reading of one
  draft: his opinions and benchmarks. Quotes are his comments, as written. Sections below up to
  [Whitethorn](#whitethorn-games-generic-service-agreement).
- **Whitethorn Games, "Generic Whitethorn Service Contract"** (a Google Doc shared publicly on 2020-12-22 by Matthew
  White, Whitethorn's CEO, with blanks for the amounts and the game, and opened to comments). Quotes from the contract
  are its wording; quotes from the comment thread are his replies, as written. See
  [its section](#whitethorn-games-generic-service-agreement).

## How to read the draft (Nijman on Raw Fury)

- "note that when reading contracts, you're reading their possibilities." Read each clause as the worst thing the
  publisher could do with it, not what it says it intends.
- Soft words carry the risk: "look for things like "not to be unreasonably withheld". what defines unreasonable?"
  "from time to time", "sole discretion" and "fair market value" are the same: ask for a number, a list or a deadline.
- A clause that reads as mutual can still put one side's job on the other: "this is written like a mutual thing but IMO
  it is up to the publisher to sell the game."
- Rights cost money: "you want rights? take out your wallet." Every right granted should match a plan and a budget.
- Money for services should be "written out and budgeted per item, not as a big opaque pile of money that could go
  anywhere from QA to marketing to porting."

## Red flags (Nijman on Raw Fury)

| Clause | Why (his comment) | Ask for |
|---|---|---|
| A markup on the advance (here 15%), repaid before anything is shared | "they still make their money back AND 15% on top of their initial investment" | Drop the markup: the publisher's reward is its share |
| A fixed revenue split whatever the budget (here 50% to the publisher of net revenue) | "it is absolutely WILD that this is fixed and not dependent on project budget/advance size. The industry standard (on the non-scummy side) up to around $100k advance is 70/30 for the dev/publisher (after costs have been recouped)." | A split that depends on the advance; his benchmark, 70/30 to the developer after recoup, for advances up to about $100k (2020) |
| No revenue to the developer until advances, markup and service spend are all recouped | "your game might make you exactly $0 if they drop the ball. note that advances paid are usually not profit, they are the money you need to live, eat, make the game, etc." | A share from the first sale, or recoup that ends sooner; plan the advance for the months after launch before store payments arrive |
| The publisher can stop paying and end the agreement at any time | "publisher can stop paying you and end the contract at any moment, under no consequence to them." | Termination for convenience only with notice, a payment and the rights back |
| After that termination, 70% of the developer's gross revenue goes to the publisher until the advance plus markup is repaid | "they can at any time cancel the contract for no reason, and then when you somehow finally manage to finish and release your game, they still make their money back AND 15% on top" | Remove: if they leave, they leave |
| On an unremedied breach the developer repays everything at once, or the game becomes theirs; buying the rights back costs "fair market value" | "If you can't repay them right away, they then own your game and all the work you've done on it so far." "note that breach of contract can be for example having a bug you can't fix within 30 days." | Remove the transfer; a cure period that fits the fault; a price fixed in the contract |
| A Final Delivery Date with severe consequences, movable only by agreement | "you are relying 100% on their good faith to change it." | Automatic extension for the publisher's own delays and changes |
| The publisher may stop selling the game, and the developer still may not | "They can unpublish your game, and you will still not be allowed to publish it yourself. Basically, they can lock up your income whenever they want." | The rights revert when the game is off sale for a set time |
| Reserves for returns taken from the developer's revenue | "why do they keep your 10% of the revenue for this instead of their own? remove this." | No reserve, or one from the publisher's share with a release date |
| Right of first refusal on sequels and DLC, and a cut of sequels made elsewhere (here 5%) | "should be taken out, at least for sequels." "they take 5% of your sequels in case you don't want to work with them???" | No cut of work they do not publish; first refusal with a short window, or none |
| Rights in books, comics, film, music and "ancillary products", with no approval | "you're signing away the book and movie (and webisode, lol) rights to your game right here" | Only the rights they have a plan and budget for, each with your approval |
| Platforms: every current platform, and any released during a 10-year term | "they also get the right to NOT publish on every platform, and every platform to come out in the coming 10(!) years." | The platforms they will release on, with dates; the rest stay yours |
| Marketing style and spend at the publisher's "sole discretion" | "you don't have a say in how they market, and also not in how they spend their marketing budget." | A marketing plan and budget in writing, with your approval |
| A right to use the source code | "they can use your source code? I don't know what this means/implies but I would ask for clarification." | Clarify and limit (porting, escrow) |
| No competing game "of the same genre and mechanics" for a year after release | "take this out of the contract. absolute non-standard nonsense." | Remove, or limit to a direct copy for a short time |
| The developer may not criticise the publisher | "you can't criticize raw fury in any way once the contract is signed" | Remove, or make it mutual and limited |
| The developer reports how it spent the advance; the publisher may audit the developer | "if you give me money it's mine and I should be able to do with it whatever I want" (his opinion) | Audit rights for the developer over the publisher's statements, not the reverse |
| Support duties: "reasonable telephone and email support", fixing "reproducible Bugs", interviews and conferences | "add: within reason. not all bugs are fixable." "conferences is a pretty big requirement here, since it implies required travel." | Limits and costs for each duty; travel paid by the publisher |

What he liked: "a evaluation of budget and timeline every 6 months", and no fixed milestone schedule ("also nice, but
does make it harder to plan that final delivery date").

## What the markup and the split cost

Illustrative numbers, not from the contract: advance C = 100,000 and net receipts R. His clause: everything goes to the
publisher until 1.15C is repaid, then 50/50, so the developer gets 0.5(R − 1.15C). His benchmark: recoup C, then 70/30
to the developer, 0.7(R − C). Neither goes below 0.

| Net receipts R | Developer, this draft | Developer, his benchmark |
|---:|---:|---:|
| 100,000 | 0 | 0 |
| 115,000 | 0 | 10,500 |
| 200,000 | 42,500 | 70,000 |
| 300,000 | 92,500 | 140,000 |
| 500,000 | 192,500 | 280,000 |

The first payment comes at 115,000 instead of 100,000, and in this range the developer earns 31% to 39% less (29% less as
sales grow without limit, the ratio of 0.5 to 0.7).

## Whitethorn Games' generic service agreement

Its model differs from the draft above: the publisher pays for its services and recoups only the development funding,
then takes a share of **gross** revenue for a fixed term, and the rights stay with the developer throughout.

### What it does that the Raw Fury draft does not

| Clause | Its wording, in short |
|---|---|
| Services at the publisher's cost | Project management, porting, QA, marketing, localization, ratings and more "are provided at the Company's expense" and "are not subject to recuperation"; only the development funding is recouped (section 1). In the thread: Whitethorn's own costs "absolutely do not" count towards recoup |
| No markup | 100% of revenue goes to the publisher until the funding "has been completely recouped", and the funding is "the full sum of recuperation" (section 10) |
| A fixed income term | Then 10% to 25% (a blank in the template) of gross revenue for 24 months from launch, renewed yearly only by a renewal both sign; without one, "all rights to The Project will return to the Client" (section 10) |
| Ownership from the start | The game's intellectual property "from inception, is and shall remain the sole property of the Client" (section 18) |
| Platforms named in the contract | Only launches listed in the addendum are covered; a new platform the publisher serves restarts 24 months for that platform; re-releases and remasters are outside the deal (section 10) |
| Limits on what the publisher can ask for | Splash screen, credits and branding in trailers each "subject to approval by Client"; at most 200 PC keys and 100 per console without consent (10-b to 10-d) |
| Dates that are not penalties | The schedule addendum's dates "are not punitive": no legal action for missing them; damages for a missed launch only after gold master and only for the developer's "gross negligence" |
| Merchandise | The developer's own merchandise is the developer's; merchandise the publisher makes splits net income 50/50, with the developer's approval of product and price (10-f) |

### What to read twice

| Clause | Why | Ask for |
|---|---|---|
| A share of **gross**, before the store's cut and taxes (section 10) | 20% of gross is about 29% of net after a 30% store cut. In the thread a commenter worked it through for a $10 sale: Steam about $3, the publisher $2, the developer $5, against $1.40 and $5.60 under 20% of net; the CEO agreed it "does ultimately change how the cash falls" | Compare offers as a share of net; for a gross share, divide by 0.7 (or 1 minus the actual store cut) |
| Gross includes "the value of platform holder funding agreements in lieu of sales" | A subscription or exclusivity deal is shared like sales | Know it is in; check it matches the services the publisher gives for that platform |
| Ending the deal costs the developer a pro-rata share of 24 months' revenue share (section 12: those invoices "are understood to be generated at the time of the execution of this agreement") | In the thread, the CEO's example: two months into a twelve-month build at 15%, about 2.5% is owed (he wrote ~2%), so that a developer cannot leave the day before launch | A cap, and no payment when the publisher is in breach (the clause already excludes that) |
| Exclusivity "for the duration of the same", with an indefinite term (sections 3 and 19) | A commenter read it as blocking another publisher for the next game; the CEO replied it covers only this game and the lawyer would clarify | Write the scope into the clause: this game, these platforms |
| Soft words: approval "not to be unreasonably withheld" (in six places), "first consideration" to the publisher's contractors | Nijman's point applies here too: what is unreasonable? | A number, a list or a deadline |
| "Time is of the essence" (section 27), though tied to the cure period | Rippon-Davies: strike it for milestones | Strike it, or keep it limited to the cure period as here |
| The publisher's liability is excluded outright (23-a), next to mutual disclaimers (23-b) | One-sided, though services cost the developer nothing | Mutual limits |
| No minimum marketing spend | The CEO: budgets vary too much, and developers rarely know what marketing costs | A marketing plan in writing, if not a sum |
| A ten-day cure for a material breach (section 5) | A commenter asked for at least a month; the CEO: "Fair." | 30 days |

### What the gross share costs

The same illustrative numbers as above: funding C = 100,000 recouped without markup from net receipts R, then a share
x of gross G = R / 0.7 (a 30% store cut), so the developer gets (1 − x / 0.7)(R − C). The Raw Fury draft and Nijman's
benchmark for comparison.

| Net receipts R | x = 10% | x = 20% | x = 25% | Raw Fury draft | Nijman's benchmark |
|---:|---:|---:|---:|---:|---:|
| 100,000 | 0 | 0 | 0 | 0 | 0 |
| 115,000 | 12,857 | 10,714 | 9,643 | 0 | 10,500 |
| 200,000 | 85,714 | 71,429 | 64,286 | 42,500 | 70,000 |
| 300,000 | 171,429 | 142,857 | 128,571 | 92,500 | 140,000 |
| 500,000 | 342,857 | 285,714 | 257,143 | 192,500 | 280,000 |

After recoup the developer keeps 86%, 71% or 64% of net, against 70% in Nijman's benchmark: 20% of gross is about the
same deal, 25% is worse. The term matters as much as the rate: the share runs 24 months from each launch, then only
by a renewal both sign; the services the developer does not pay for are not in these numbers.
