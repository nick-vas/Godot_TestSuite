# Store pages, ratings, privacy, licences and credits: sources

The research behind the `godot-store-page`, `godot-legal`, `godot-credits` and `godot-release-readiness` skills, the
`credits` command and `doctor`'s Steam store art check, gathered on 2026-10-21. Pages were fetched as served that day;
store rules change, so check the source before relying on a number. **General information for developers, not legal
advice.**

Marks: **tested** means run here (Godot 4.7.2 mono on Linux); **unconfirmed** means only a secondary source was found, or
sources disagree. Everything else was read in the source named.

## Sources

| Source | What it gave |
|---|---|
| [Steamworks: store graphical assets](https://partner.steamgames.com/doc/store/assets) (and the standard, library, community and rules pages under it) | Capsule, library and screenshot sizes since August 2024 ("Old dimensions are no longer accepted"); the rules for text on capsules (effective 1 September 2022) |
| [Steamworks: trailers](https://partner.steamgames.com/doc/store/trailer) | Upload formats, the order trailers and screenshots appear in, the 6-second microtrailer built from the first video, no release while a trailer encodes |
| [Steamworks: description](https://partner.steamgames.com/doc/store/page/description), [tags](https://partner.steamgames.com/doc/store/tags) | Short description "limited to a few hundred characters", plain text, mention the genre; at least 5 tags before launch, up to 20 |
| [Steamworks: onboarding](https://partner.steamgames.com/doc/gettingstarted/onboarding), [app fee](https://partner.steamgames.com/doc/gettingstarted/appfee) | US$100 per app, recouped after US$1,000; 21 days between paying and releasing |
| [Steamworks: releasing](https://partner.steamgames.com/doc/store/releasing), [review process](https://partner.steamgames.com/doc/store/review_process), [coming soon](https://partner.steamgames.com/doc/store/coming_soon), [release dates](https://partner.steamgames.com/doc/store/release_dates) | A Coming Soon page for at least two weeks; 3 to 5 business days per review, submit 7 ahead, the page before the build; the date freezes two weeks out; the manual Release App button |
| [Steamworks: wishlists](https://partner.steamgames.com/doc/marketing/wishlist) | When wishlist emails go out; "two years ahead ... just as likely to purchase as ... two weeks ahead" |
| [Steamworks: Steam Next Fest](https://partner.steamgames.com/doc/marketing/upcoming_events/nextfest) and the February 2027 page | One Next Fest per game; the workback (demo review 3 weeks before, 5 for the press preview); February 2027: register by January 10, runs February 22 to March 1 |
| [Steamworks: Content Survey](https://partner.steamgames.com/doc/gettingstarted/contentsurvey), Germany and Indonesia pages | The survey before review (general content, mature content, generative AI); Germany since 15 November 2024; no IARC-generated USK ratings on Steam |
| [Steam refunds](https://store.steampowered.com/steam_refunds), [Steam Subscriber Agreement](https://store.steampowered.com/subscriber_agreement) | 14 days and under 2 hours of play; the SSA's licence and "an end user license agreement specific to a particular game" |
| Chris Zukowski, [How many wishlists should I have](https://howtomarketagame.com/2022/09/26/how-many-wishlists-should-i-have-when-i-launch-my-game/) (updated June 2026) and the [archived 7,000 version](https://howtomarketagame.com/2022/09/25/archive-how-many-wishlists-should-i-have-when-i-launch-my-game/) | The 7,000 rule archived after Valve's Personalized Calendar; tiers Bronze 5,000, Silver 8,000, Gold 50,000, Diamond 90,000 |
| Zukowski, [Benchmarks](https://howtomarketagame.com/benchmarks/) | Weekly wishlists and demo playtime by tier; the first-week conversion table is labelled as Simon Carless's, June 2020 |
| Zukowski, [Next Fest benchmarks](https://howtomarketagame.com/2025/03/26/benchmarks-how-many-wishlists-can-i-get-from-steam-next-fest/) (updated April 2026) | 182 responses from February 2026: median gain by going-in wishlists; Spearman r = 0.825 |
| Zukowski, [Steam page checklist](https://howtomarketagame.com/wp-content/uploads/2020/03/SteamPageChecklistv1.pdf) (2020) and posts on capsules, trailers, tags and timing | First 4 screenshots show the core loop; the short description names the hook with verbs; top 5 tags; "DO NOT DO YOUR OWN CAPSULE ART" (his opinion) |
| [itch.io creator docs](https://itch.io/docs/creators/getting-started) and quality guidelines | Cover 630x500 recommended, 315x250 minimum; label adult content and generative AI |
| [Epic storefront media guide](https://dev.epicgames.com/docs/epic-games-store/sales-and-marketing/marketing/storefront-media-guide) | Logo 960x540 PNG; landscape 2560x1440 and portrait 1200x1600 images |
| [IARC](https://www.globalratings.com/how-iarc-works/) (how it works, FAQ, participants, storefronts) | Free to developers; the rating authorities; the storefronts (Steam is not one) |
| [Google Play: content ratings](https://support.google.com/googleplay/android-developer/answer/9898843), [user data](https://support.google.com/googleplay/android-developer/answer/10144311), [Data safety](https://support.google.com/googleplay/android-developer/answer/10787469) | IARC rating required, unrated apps removed; a privacy policy for every app, in Play Console and in the app |
| [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) 5.1.1 | A privacy policy link in App Store Connect and in the app |
| [PEGI: what do the labels mean](https://pegi.info/what-do-the-labels-mean) | Since June 2026: paid random items PEGI 16 (18 social casino); time-limited offers, pressure to play, unrestricted communication |
| [ESRB ratings guide](https://www.esrb.org/ratings-guide/) | Interactive elements, which "do not influence the rating assignment" |
| GDPR Articles 8 and 13 ([legislation.gov.uk, as adopted](https://www.legislation.gov.uk/eur/2016/679/contents/adopted); EUR-Lex returned an empty page) | What a privacy notice must say; a child's consent from 16, member states may lower it to 13 |
| [SPDX license-list-data](https://github.com/spdx/license-list-data) 3.29.0 | The licence texts in `ci/godot/templates/licences/` and what each asks |
| [Creative Commons: recommended practices for attribution](https://wiki.creativecommons.org/wiki/Recommended_practices_for_attribution) | TASL (title, author, source, licence); title required in 3.0 and earlier |
| [Godot: complying with licenses](https://docs.godotengine.org/en/stable/about/complying_with_licenses.html) | Include the MIT text somewhere; ship COPYRIGHT.txt for third-party components |
| Chris Reed, [Practical Contract Law 201 for Indie Developers](https://www.youtube.com/watch?v=t8UFJ3obm-Q) (GDC, about 2017; US law; notes in [gdc/contract-law-201.md](gdc/contract-law-201.md)) | The maker owns the copyright unless a signed work-for-hire or assignment says otherwise, owners included; games pulled from Steam by a former contractor's DMCA notice; `assets.json`'s commissioned entries |
| [IGDA Game Crediting Guide 10.1](https://igda.org/wp-content/uploads/2021/11/IGDA-Game-Crediting-Guidelines-10.1-March-2023.pdf) (March 2023) | Who is credited, the order, names as people want them; "Credits must not be hidden or locked" |
| Tim Rippon-Davies, [Contract Killers: What Developers Should Eliminate From Their Publishing Agreement](https://www.youtube.com/watch?v=yfrwQnqwPps) (GDC, about 2021, not stated; a London lawyer, common-law contracts; notes in [gdc/contract-killers.md](gdc/contract-killers.md)) | `godot-legal` section 6: licence term and what it counts from, auto-renewal, review windows with deemed approval, payment lag, recoup source, third-party marketing costs, first refusal instead of rights, tool carve-outs, cure periods, "time is of the essence", statements and audit. One lawyer's opinion, not rules |

## Tested here

- `Engine.get_license_text()`, `get_copyright_info()` (102 components) and `get_license_info()` (19 licence texts, keyed
  by Debian-style names such as `Expat`) in Godot 4.7.2. The Godot logo is CC-BY-4.0; FreeType's licence asks binary
  releases to say they are based in part on the FreeType Team's work. The list covers every platform's components, not
  only what one export compiles in. `ci/godot/tools/notices.gd` dumps it for `credits`.
- A Godot 4.7.2 C# Linux export (Breakout, 189 files in its data folder) contains no .NET licence or notices file. The
  runtime pack in the NuGet cache has `THIRD-PARTY-NOTICES.TXT`; `credits` appends it for C# games.
- `doctor`'s store art check on generated PNG and JPEG files of right and wrong sizes (`tests/Test-Store.ps1`), and the
  credits generator on a sample manifest (`tests/Test-Credits.ps1`).

## Mistakes an agent is likely to make

1. The old capsule sizes (460x215, 231x87, 616x353, 374x448), refused since August 2024.
2. "You need 7,000 wishlists" as a rule; its author archived it in June 2026.
3. A 30-day wait after the Steam Direct fee (now 21), and forgetting the 2-week Coming Soon minimum, the 7-business-day
   review lead, the date freeze and the manual release button.
4. Treating Steam as an IARC store, or entering an IARC-generated USK rating on Steam.
5. Missing PEGI's June 2026 change for paid random items.
6. Saying Steam needs no rating: Germany and Indonesia need one, which the Content Survey gives.
7. Crediting Godot with only its MIT text, or only FreeType, ENet and mbedTLS (an older version of Godot's page); and
   shipping a C# game without the .NET notices.
8. An MIT credit on screen without the licence text shipped; or a CC BY credit only in a file nobody sees.
9. First-week conversion figures attributed to Zukowski (they are Carless's, from 2020).
10. Calling OGA-BY an SPDX id (it is not one), or treating bought asset packs as free of obligations.
11. "We collect nothing, so no privacy policy": Google Play and the App Store require one anyway.

## Unconfirmed or not reached

- The short description's exact limit (300 characters is from third parties) and the capsules' file formats and size caps.
- Whether a trailer is still required for Steam's review: the trailer page says so, the Coming Soon page says "ideally",
  and Zukowski (March 2025) says Valve removed the requirement.
- How a custom EULA is configured on Steam, and whether Steam requires a game's own privacy policy (not in public pages).
- Whether Steam's DRM wrapper counts as an "effective technological measure" under CC BY 3.0 and 4.0 (OGA-BY exists
  because artists objected to that clause): a legal question, flagged rather than answered.
- IARC's exact questions (only inside store portals).
- The COPPA amendment dates (effective June 2025, compliance April 2026) and the Belgian loot box report: secondary
  sources only.
- GodotSteam's licence page, the Steamworks SDK redistribution terms, FMOD's credit terms and GOG's asset specs: not
  reachable from the session or not public.
- Whether an export template's `get_copyright_info()` lists only the components it compiles in.
