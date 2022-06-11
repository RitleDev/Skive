extends Node


func _on_Button_pressed():
	# Making the parent start a request to emit a signal.
	get_parent().ClickedButton(self.name.replace('-', '.'))
