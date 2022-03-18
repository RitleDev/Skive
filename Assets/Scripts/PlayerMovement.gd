extends KinematicBody2D

export (float) var speed = 200
export (float) var friction = 0.25
var input_enabled = false


# Variables:
var velocity = Vector2()


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

# Called every physics frame 
# (for this project it is 0.01 seconds)
func _physics_process(_delta):
	if input_enabled:
		get_input()
		velocity = move_and_slide(velocity)
	

func get_input():
	velocity = Vector2()
	if Input.is_action_pressed('right'):
		velocity.x += 1
	else:
		# slow down when there's no input
		velocity.x = lerp(velocity.x, 0, friction)
	if Input.is_action_pressed('left'):
		velocity.x -= 1
	if Input.is_action_pressed('up'):
		velocity.y -= 1
	if Input.is_action_pressed('down'):
		velocity.y += 1
	velocity = velocity.normalized() * speed
	

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass


func _on_Panel_enable_movement():
	input_enabled = true
