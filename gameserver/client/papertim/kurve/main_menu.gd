extends Control
var player_nums : Array[int] = []
# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


func _process(delta):
	if Input.is_action_just_pressed("p1_left") or Input.is_action_just_pressed("p1_right"):
		if !player_nums.has(1):
			player_nums.append(1)
			$RootVBox/VBoxContainer/BlueContainer/CheckMark.visible = true
	if Input.is_action_just_pressed("p2_left") or Input.is_action_just_pressed("p2_right"):
		if !player_nums.has(2):
			player_nums.append(2)
			$RootVBox/VBoxContainer/OrangeContainer/CheckMark.visible = true
	if Input.is_action_just_pressed("p3_left") or Input.is_action_just_pressed("p3_right"):
		if !player_nums.has(3):
			player_nums.append(3)
			$RootVBox/VBoxContainer/GreenContainer/CheckMark.visible = true
	if Input.is_action_just_pressed("p4_left") or Input.is_action_just_pressed("p4_right"):
		if !player_nums.has(4):
			player_nums.append(4)
			$RootVBox/VBoxContainer/PurpleContainer/CheckMark.visible = true
	
	if player_nums.size() >= 1:
		$RootVBox/LabelStart.visible = true
		if Input.is_action_just_pressed("ui_accept"):
				GlobalData.player_nums = player_nums
				get_tree().change_scene_to_file("res://kurve/game.tscn")
