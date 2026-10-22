# Chat that every player can use (godot-multiplayer reference)

From Karen Stevens (EA Sports accessibility lead, GDC Summer 2020) and Tara Voelker (Evolve); notes in
`${CLAUDE_PLUGIN_ROOT}/docs/gdc/folds-accessibility.md`. Chat between people is also covered by US law when the game is
sold there: the CVAA section of `godot-legal`. The Xbox Accessibility Guidelines 119 and 120 (`docs/wcag-ui.md`) say the
same from the platform side.

- **One window** for everything said: typed messages and voice transcribed to text land in the same scrolling list, so a
  deaf player looks in one place. Keep about 100 lines of history to scroll back through. The player can move it, resize
  it and set its opacity, choosing contrast or a view of the game behind it.
- **Typing never stops play**: the window opens over the running game, not in a pause menu. No action needs several
  buttons held at once, sticks and D-pad included.
- **Who is talking**: a speaking icon next to each player while their microphone is live. Someone who cannot hear may not
  know voice chat is happening at all, and the icon tells them to turn on transcription.
- **Quick messages**: a wheel or list of canned phrases, different by context where it helps (attack and defence), and
  contextual pings on what the player points at (Apex Legends' ping). Let players pick their phrases. They are what a
  player without a microphone has: on console, Evolve had no other way to talk to the team, and the comm wheel it built
  for that placed a marker in the world. Keep text chat too, since canned phrases never cover everything.
- **Read aloud, as an option**: incoming text spoken with `DisplayServer.TtsSpeak` (check
  `DisplayServer.TtsGetVoicesForLanguage` first; `godot-ui-accessibility` has a sample), and emotes narrated. Speech to
  text and text to speech are separate settings, neither tied to the other.
- **Keyboard**: the platform's on-screen keyboard is already narrated; a keyboard of the game's own must be narrated too.
- The settings for all of this are reachable from the first-boot screen and the pause menu, since getting to the chat
  is part of the chat (`godot-ui-accessibility`).

Moderation (scoring, warn, mute, report, rate limits) is `ChatGuard` in `godot-servers`.

Transcription and speech services in the cloud add a delay and usually a fee per request; a local engine answers sooner
(Stevens). Godot has text to speech built in, not speech to text.
