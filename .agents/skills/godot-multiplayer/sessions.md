# Lobbies, host migration and crossplay (godot-multiplayer reference)

Rules from several GDC talks; sources and what was left out: `${CLAUDE_PLUGIN_ROOT}/docs/gdc/folds-l10n-audio-net.md`.

## Lobbies and menus (Drew Ehrich, The Maestros, GDC 2020)

- **A session connection, not HTTP polling.** Between two HTTP requests the server cannot tell whether a player is still
  there, and it cannot push a change: polling plus home-made heartbeats follows. Use a connection that has a session
  (`WebSocketPeer`, or the game's own ENet peer), so a change arrives at once and a leave or a drop is an event.
- **Send the whole lobby on every change** (players, map, ready flags) as one reliable message. Deltas still need a full
  resend for a client that missed one, so they cost both. This is for small, fixed-size state like a lobby, not the game.
- **One backend service until scale demands more.** His split into microservices cost months of deploy tooling, and
  account creation became a chain of calls that left half-made players when one step failed.
- **One quick-play queue** while the player count is uncertain (a Sony online consultant's GDC advice): each extra
  queue or bucket splits the players and lengthens every wait. Custom games go through invites.
- Boot straight into a match from the command line (`--level=X`, `godot-automation-hooks`) before wiring platform
  invites: an accepted invite then goes straight into the game, past the menus.

## Linked state and host migration (Destiny, Justin Truman, Bungie)

- **State a script links must travel together.** A switch that opens a door: if "switch on" arrives and "door open" is
  lost when the host leaves, the new host has a pressed switch and a closed door, a blocker on the critical path
  (Halo: Reach shipped migration bugs like this, such as a duplicated flag). Put linked values in one state group or
  one reliable message, never as separately prioritised objects (section 3).
- **With host migration, declare what the objectives depend on.** Destiny's scripts listed up front the small state
  they read (a squad's alive count, not its positions), kept it on a host that never migrates, updated it as one atomic
  message 10 times a second, and on each migration made the new host match it (spawn or kill to reach the count)
  through the same code as a normal update; join-in-progress came from the same path. A player in a public area saw
  a host migration every 160 s on average, so test it as a normal event, not an edge case.
- **Progression never runs only where a player can cut it off.** A raid boss's critical step lived in client-side
  damage logic, so pulling the host's network cable at the right moment beat it, and it became the usual way to win
  (`godot-anti-cheat` section 2).

## Crossplay (Destiny 2, John Chu, Bungie, GDC 2022 inferred)

- **Split competitive pools by platform security, never by input device.** Destiny 2 kept consoles (cloud streaming
  included) and PC apart in competitive modes only; a player can swap a controller for a mouse after matchmaking, so an
  input pool means nothing. A mixed party goes to the PC pool: crossing is one-way, console into PC.
- **A block covers every account the player has linked**, on every platform, or a harasser just switches platform.
  Blocking was a condition of shipping.
- **Filter names imported from platforms** with the game's own filter: platforms filter names to different standards.
  Read each platform's crossplay certification first: some require their own display name, and some forbid other
  platforms' icons (`godot-console-cert`).
- Send ids that mean the same everywhere, never local handles (memory or package offsets differ per platform build).

## Replication traps (Sony online crash course)

- Many replication systems skip a zero, null or default value: a health of 0 or an emptied slot is never sent. Test
  that each replicated property can change to its default and that clients see it.
- Replicate only what others need (a position, not the whole object).
