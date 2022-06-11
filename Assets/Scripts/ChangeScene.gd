extends Node


signal scene_changed(scene_name)  # Setting signal to change scene.

export (String) var scene_name = ''  # Picking a scene through the editor.


func _on_ClientButton_pressed():
	emit_signal('scene_changed', scene_name)  # Emmiting the signal upon click.

func request_scene_change(ip: String):
	# Emitting the signal upon click of a generated button in runtime.
	# This is being used by Discover.gd 
	emit_signal('scene_changed', scene_name)
