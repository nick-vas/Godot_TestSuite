extends Node

# The good counterpart: port and client limit only.
func host(port: int) -> void:
	var peer := ENetMultiplayerPeer.new()
	peer.create_server(port, 64)
	multiplayer.multiplayer_peer = peer
