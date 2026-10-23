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
  one bigger, which got lost too. TRIBES II capped it; the C# example sends each input in 3 packets.
- **Events in the state packets.** TRIBES builds guaranteed events on the same notify layer as ghosts: "if the
  Connection manager signals nondelivery then the events associated with the lost packet are simply pushed onto the
  head of the event queue for re transmission", and the receiver acts on guaranteed events in order. In Godot, a
  `Reliable` RPC and a `MultiplayerSynchronizer` or replicator are separate streams, so nothing orders an event against
  the object it names. The C# example's `Net/EventStream.cs` writes events after the packet's ghosts, numbers the guaranteed
  ones, sends one naming a ghost only once that ghost's creation is in the same packet or acknowledged
  (`GhostReplicator.AwaitingCreation`), and puts a lost packet's events back by number (pushing them onto the head in
  turn would swap the events of two packets lost in a row). The client applies a packet's ghosts first, then its events;
  `EventReceiver` holds a guaranteed event that arrives early until the ones before it come. Unguaranteed events are
  sent once. An event can still arrive after its object left the client's scope: treat a missing object as gone.
- **Bit packing.** "Virtually all data is transmitted using the smallest number of bits possible": bools in 1 bit,
  ints in the bits their range needs, floats quantised. `Net/BitPacker.cs` (`BitWriter`, `BitReader`, `BitPacking`)
  does this over a `byte[]`, since `StreamPeerBuffer` works in whole bytes; a quantised float comes back within half a
  step, and a reader that disagrees with its writer throws (past the end, or a byte or more left at `Finish()`).
  `GhostReplicator` still charges a flat 4 bytes a value; a packed group is usually far smaller.
- **The receiver sets the rate.** Each client states the packets a second and bytes a packet it can receive ("these
  parameters are set by the remote host's Stream manager and represent the amount of data it's capable of receiving";
  10 packets of 200 bytes is about 2 KB/s), and may change them while connected; the server caps each client by its
  own uplink. Godot has no such negotiation: send the numbers in the auth exchange or a settings RPC, and use them as
  the replicator's send interval and byte budget. The authors left open scaling each client's share with the number
  of clients, and measuring the rate instead of setting it by hand.
- **Static data by id.** Each vehicle sent the id of its definition (TRIBES' datablocks), loaded once at connection,
  not the definition itself (`godot-data`).

Measured with `ReplicationTests` (80 objects, 4 groups each, 8 changes a tick, 30 packets a second of at most 400 bytes,
20% loss and 120 ± 30 ms each way): the client ends with exactly the objects in its scope and their current values,
never applies an older value over a newer one, and partial updates use 5% of the bytes full snapshots would; 151 lost
values were not resent because newer ones were already sent. When 200 objects entered scope at once, the uncapped
replicator sent the opponent nothing for 10 packets in a row; capped at 4, it missed at most 1, and all 200 objects
still arrived within 12 packets (10 uncapped).

Measured with `EventStreamTests` (60 objects appearing over 20 s, each one's spawn event posted the tick after it
enters scope, a guaranteed hit every third tick and an unguaranteed footstep every tick, 400-byte packets with 100 left
for events, 20% loss and 120 ± 30 ms each way): every guaranteed event arrived exactly once and in order; 11 events
reached the client before their object when events ignored the ghosts (as a separate reliable channel would), 0 with
the wait. `BitPackerTests`: a position at 1/1024 m in -1024..1024 takes 22 bits and comes back within 1/2048 m.
