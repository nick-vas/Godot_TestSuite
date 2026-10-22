# Sending state to many players: the TRIBES model (godot-multiplayer reference)

The table of data kinds is in SKILL.md section 3.

- `OnChange` replication sends "using reliable transfer mode when its value changes" (Godot's class reference): good
  for values that change rarely (team, name, score), wrong for ones that change all the time. Under loss a reliable
  channel resends every stale value, in order, and newer values wait behind them. `Always` sends unreliably, but every
  property every interval.
- **Notify, never resend.** The connection layer numbers unreliable packets, and the acknowledgements tell the sender,
  packet by packet and in order, what arrived (a packet arriving after a newer one counts as lost and is discarded, so
  old state never overwrites new). It retransmits nothing; each kind of data decides what a loss means.
- **State masks.** Each object has state groups (position, health, animation...), one dirty bit each, per client. A
  packet takes the dirty groups' current values and clears the bits. On a loss, a bit is set again only if no later
  packet carried that group: a newer value is already on its way, so the old one is never resent.
- **Scope and priority.** Each client gets only the objects in its scope (in view, near, relevant), most important
  first, within a byte budget per packet. Godot's visibility filters (`PublicVisibility = false`,
  `AddVisibilityFilter`, `SetVisibilityFor`) give the scope; nothing in Godot gives priority or a budget. Rank by
  distance, size on screen and heading towards the player, and let waiting raise an object's rank, so bandwidth is
  shared in proportion to priority and nothing starves.
- **Cap what jumps the queue.** Creations, deletions and anything overdue go ahead of priority order; a burst of them
  (200 objects entering scope, a pile of crates disturbed together and ageing in step) fills whole packets while the
  player being fought gets nothing. Let a fixed number jump per packet (`GhostReplicator.MaxOverridesPerPacket`,
  default 4), the rest wait their turn by priority, and give background data (end-of-match statistics) at most a share
  of each packet (Halo: Reach: 10%).
- **Inputs.** TRIBES first resent every unacknowledged move in each packet: on a slow link a lost packet made the next
  one bigger, which got lost too. TRIBES II capped it; Breakout sends each input in 3 packets.
- **Static data by id.** Each vehicle sent the id of its definition (TRIBES' datablocks), loaded once at connection,
  not the definition itself (`godot-data`).

Measured with `ReplicationTests` (80 objects, 4 groups each, 8 changes a tick, 30 packets a second of at most 400 bytes,
20% loss and 120 ± 30 ms each way): the client ends with exactly the objects in its scope and their current values,
never applies an older value over a newer one, and partial updates use 5% of the bytes full snapshots would; 151 lost
values were not resent because newer ones were already sent. When 200 objects entered scope at once, the uncapped
replicator sent the opponent nothing for 10 packets in a row; capped at 4, it missed at most 1, and all 200 objects
still arrived within 12 packets (10 uncapped).
