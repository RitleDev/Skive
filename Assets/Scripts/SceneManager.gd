extends Node

onready var current_scene = $Main

func _ready():
	current_scene.connect('scene_changed', self, 'handle_scene_changed')

# This function actually switches between the scenes
func handle_scene_changed(scene_name: String):
	print('Assets/Scenes/' + scene_name + '.tscn')
	var next_scene = load('Assets/Scenes/' + scene_name + '.tscn').instance()
	add_child(next_scene)
	next_scene.connect('scene_changed', self, 'handle_scene_changed')
	current_scene.queue_free()
	current_scene = next_scene
