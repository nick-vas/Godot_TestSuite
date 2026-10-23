extends CanvasLayer
## The pause menu. It runs while the tree is paused (process mode Always) so Escape and its buttons still work.

signal quit_pressed

@onready var _resume: Button = $ResumeButton
@onready var _quit: Button = $QuitButton
@onready var _title: Label = $Title


func _ready() -> void:
	visible = false
	_resume.pressed.connect(close)
	_quit.pressed.connect(_on_quit)
	_refresh_text()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()


func _refresh_text() -> void:
	_title.text = tr("PAUSE_TITLE")
	_resume.text = tr("PAUSE_RESUME")
	_quit.text = tr("PAUSE_QUIT")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()


func open() -> void:
	visible = true
	get_tree().paused = true


func close() -> void:
	visible = false
	get_tree().paused = false


func _on_quit() -> void:
	close()
	quit_pressed.emit()


func _exit_tree() -> void:
	# A game freed while paused must not leave the whole tree paused behind it.
	if visible:
		get_tree().paused = false
