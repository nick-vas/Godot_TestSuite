extends Node

func _ready() -> void:
	print(tr("HELLO"), tr("Options"), tr_n("%d coin", "%d coins", 3))
	print(tr("NOT_IN_ANY_TABLE"))
