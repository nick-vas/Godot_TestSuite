extends Node

func host(port: int) -> void:
	var peer := ENetMultiplayerPeer.new()
	peer.create_server(port, 64, 3)
	multiplayer.multiplayer_peer = peer
