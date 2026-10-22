# United States: the CVAA (godot-legal reference)

Read in 47 CFR Part 14 (the 2023 edition, from govinfo.gov; the FCC's own pages could not be reached from here). The
games-specific dates are from a GDC talk (AbleGamers and Level Access, about 2019): check them before relying on them.

- **What it covers:** "advanced communications services" between people: real-time text chat, messaging, voice and video
  chat. Not messages from bots or the game. The path to the chat counts too: finding, opening and setting it up (the
  menus, matchmaking and friends lists that lead to it; Xbox Accessibility Guideline 120).
- **Games** lost their waiver on 1 January 2019, as the talk says; one released earlier is covered once it gets a major
  change (its example: an expansion like World of Warcraft's Cataclysm). The rules' small-business exemption expired in
  2013 (14.4(c)), so size alone does not exempt a studio.
- **Third-party chat** (a voice or text service built in): the provider carries the communication itself; getting to it
  from the game stays yours (14.2, as the talk explained it).
- **What the rules ask** (14.20, 14.31): accessible and usable "unless ... not achievable" (reasonable effort or expense,
  14.10(b)); accessibility considered from design onward; and records kept until two years after the game stops being
  offered: how people with disabilities were consulted, a description of the accessibility features, and compatibility
  with the devices they use.
- **Every 1 April**, an officer files a certificate with the FCC that those records are kept, with a contact for
  accessibility complaints (14.31(b)). The talk adds that the FCC first works through complaints informally (192, one went
  formal, at the time), and that an accessibility page and a design checklist by functional need are what answers one.
- In practice: a checklist per feature by need (blind, low vision, deaf, motor, cognitive), playtests with disabled
  players (AbleGamers runs a player panel), the accessibility feature page (XAG 121) and an accessible support channel
  (XAG 122). Chat design itself: `godot-multiplayer` ([chat.md](../godot-multiplayer/chat.md)).
