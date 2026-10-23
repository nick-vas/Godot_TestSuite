# A minimal networked game for `hyperdot.ps1 soak`: one headless server, N headless clients over ENet on localhost.
# The kit starts each process with --soak-role=server|client, --soak-port and --soak-id; the game prints
# "[soak] ready", "[soak] metric <name> <value>" and, when it finds something wrong, "[soak] fail <reason>".
# --leak makes the server keep memory it never frees; --crash-after=<s> makes it quit early: the self-test's broken cases.
# The server reports input_loss_pct (inputs it never saw, counted from gaps in each client's sequence numbers) and
# frame_ms_max (its longest real frame): both rise when junk traffic crowds legitimate packets out of the socket buffer,
# which is what `soak -JunkPps` floods the port to measure. Each client reports its last and worst round trip.
extends Node

var _role := ""
var _port := 0
var _id := 0
var _leak := false
var _crash_after := -1.0
var _elapsed := 0.0
var _positions := {}          # server: peer id -> Vector2
var _hoard := []              # server, with --leak
var _sequence := 0
var _last_metric := 0.0
var _rtt_ms := -1.0
var _rtt_max_ms := 0.0
var _states_received := 0
var _last_seq := {}           # server: peer id -> last input sequence seen
var _inputs_applied := 0      # server: inputs delivered
var _inputs_lost := 0         # server: inputs missing from sequence gaps
var _frame_ms_max := 0.0      # server: longest real frame, after warm-up
var _last_frame_usec := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var value := arg.get_slice("=", 1)
		match arg.get_slice("=", 0):
			"--soak-role": _role = value
			"--soak-port": _port = int(value)
			"--soak-id": _id = int(value)
			"--leak": _leak = true
			"--crash-after": _crash_after = float(value)
	var peer := ENetMultiplayerPeer.new()
	if _role == "server":
		var err := peer.create_server(_port, 64)
		if err != OK:
			print("[soak] fail server could not listen on %d: %s" % [_port, error_string(err)])
			return
		multiplayer.multiplayer_peer = peer
		multiplayer.peer_connected.connect(func(id): _positions[id] = Vector2.ZERO)
		multiplayer.peer_disconnected.connect(func(id): _on_peer_left(id))
		print("[soak] ready")
	elif _role == "client":
		peer.create_client("127.0.0.1", _port)
		multiplayer.multiplayer_peer = peer
		multiplayer.connected_to_server.connect(func(): print("[soak] ready"))
		multiplayer.connection_failed.connect(func(): print("[soak] fail could not connect"))
		multiplayer.server_disconnected.connect(func(): print("[soak] fail the server went away"))


func _on_peer_left(id: int) -> void:
	_positions.erase(id)
	_last_seq.erase(id)


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _role == "server":
		if _crash_after >= 0 and _elapsed > _crash_after:
			get_tree().quit(3)
		if _leak:
			_hoard.append(PackedFloat32Array(range(4096)))   # 16 KB a tick, never freed
		var now := Time.get_ticks_usec()
		if _last_frame_usec > 0 and _elapsed > 2.0:   # skip the warm-up, where connecting peers spike the frame time
			_frame_ms_max = max(_frame_ms_max, (now - _last_frame_usec) / 1000.0)
		_last_frame_usec = now
		var state := PackedVector2Array()
		for id in _positions:
			state.append(_positions[id])
		if Engine.get_physics_frames() % 3 == 0:
			receive_state.rpc(state)
		if _elapsed - _last_metric >= 5.0:
			_last_metric = _elapsed
			var total := _inputs_applied + _inputs_lost
			var loss := 0.0
			if total > 0:
				loss = 100.0 * _inputs_lost / total
			print("[soak] metric clients %d" % _positions.size())
			print("[soak] metric input_loss_pct %.1f" % loss)
			print("[soak] metric frame_ms_max %.1f" % _frame_ms_max)
	elif _role == "client" and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_sequence += 1
		send_input.rpc_id(1, _sequence, Vector2(sin(_elapsed + _id), cos(_elapsed)))
		if _sequence % 30 == 0:
			ping.rpc_id(1, Time.get_ticks_usec())
		if _elapsed - _last_metric >= 5.0:
			_last_metric = _elapsed
			print("[soak] metric rtt_ms %.1f" % _rtt_ms)
			print("[soak] metric rtt_max_ms %.1f" % _rtt_max_ms)
			print("[soak] metric states %d" % _states_received)


@rpc("any_peer", "unreliable_ordered")
func send_input(seq: int, direction: Vector2) -> void:
	var from := multiplayer.get_remote_sender_id()
	if _last_seq.has(from) and seq > _last_seq[from] + 1:
		_inputs_lost += seq - _last_seq[from] - 1   # ordered delivery skipped these: they were dropped, not reordered
	_last_seq[from] = seq
	_inputs_applied += 1
	if _positions.has(from):
		_positions[from] += direction.limit_length(1.0) * 4.0


@rpc("authority", "unreliable_ordered")
func receive_state(_state_positions: PackedVector2Array) -> void:
	_states_received += 1


@rpc("any_peer", "reliable")
func ping(sent_usec: int) -> void:
	pong.rpc_id(multiplayer.get_remote_sender_id(), sent_usec)


@rpc("authority", "reliable")
func pong(sent_usec: int) -> void:
	_rtt_ms = (Time.get_ticks_usec() - sent_usec) / 1000.0
	_rtt_max_ms = max(_rtt_max_ms, _rtt_ms)
