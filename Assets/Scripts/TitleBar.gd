extends Control

var following = false
onready var dragging_start_position = Vector2()

func _on_TitleBar_gui_input(event):
	if event is InputEventMouseButton:  # Checking event type.
		if event.get_button_index() == 1:  # Checking for left click.
			following = !following
			dragging_start_position = get_local_mouse_position()


func _process(_delta):
	if following:
		# Setting window position to the current position
		# GetGlobalPosition is the position relative to the origin point of
		# the GUI application (Origin is top left)
		# Draggnig start position is taking care of the Title bar pivot offset.
		OS.set_window_position(OS.window_position + get_global_mouse_position()
		- dragging_start_position)
