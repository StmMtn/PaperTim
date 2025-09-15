extends Node2D

@export var player_packed: PackedScene
@export var spawn_bounds_x: Vector2 = Vector2.ZERO
@export var spawn_bounds_y: Vector2 = Vector2.ZERO
@export var network_driven: bool = false

var players: Dictionary = {}
var trails: Array = []
var remaining_players: int
var round_running := false

func _ready() -> void:
	randomize()
	if not network_driven:
		for n in GlobalData.player_nums:
			var new_player = player_packed.instantiate()
			new_player.use_local_input = true 
			new_player.spawn_trail.connect(_on_spawn_trail)
			add_child(new_player)
			new_player.player_num = n
			players[n] = [new_player, 0]
	if not network_driven:
		call_deferred("start_round")


func start_round() -> void:
	# Clear previous trails
	for t in trails:
		t.queue_free()
	trails.clear()
	
	# Reset Players
	for p in players:
		players[p][0].position = Vector2(
			randf_range(spawn_bounds_x.x, spawn_bounds_x.y),
			randf_range(spawn_bounds_y.x, spawn_bounds_y.y)
		)
		players[p][0].start()
	remaining_players = players.size()
	round_running = true
	print("start_round(): players=", players.size())
	$RoundStartTimer.start()

func _process(delta: float) -> void:
	var fps := $UI/Control/VBoxContainer.get_node_or_null("FPSCounter")
	if fps and fps.visible:
		fps.text = str(Engine.get_frames_per_second())

	# Collision
	for p in players:
		if player_collision(players[p][0]):
			players[p][0].set_active(false)
			remaining_players -= 1
			if remaining_players <= 1:
				round_over()
	
	# Check if should exit
	if Input.is_action_just_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://kurve/main_menu.tscn")

func round_over() -> void:
	$RoundOverTimer.start()
	round_running = false
	if remaining_players == 1:
		for p in players:
			if players[p][0].is_alive():
				# Update Score
				players[p][0].set_active(false)
				players[p][1] += 1
				match players[p][0].player_num:	
					1:
						$UI/Control/VBoxContainer/LabelBlue.text = "BLUE: %s" % players[p][1]
						$UI/Control/VBoxContainer/LabelRoundOver.text = "BLUE WINS!"
					2:
						$UI/Control/VBoxContainer/LabelOrange.text = "ORANGE: %s" % players[p][1]
						$UI/Control/VBoxContainer/LabelRoundOver.text = "ORANGE WINS!"
					3:
						$UI/Control/VBoxContainer/LabelGreen.text = "GREEN: %s" % players[p][1]
						$UI/Control/VBoxContainer/LabelRoundOver.text = "GREEN WINS!"
					4:
						$UI/Control/VBoxContainer/LabelPurple.text = "PURPLE: %s" % players[p][1]
						$UI/Control/VBoxContainer/LabelRoundOver.text = "PURPLE WINS!"
				return
	else:
		$UI/Control/VBoxContainer/LabelRoundOver.text = "IT'S A DRAW!"

func player_collision(player) -> bool:
	if not player.is_alive():
		return false
	var ignore_last_segments := 6  
	for t in trails:
		var pts: PackedVector2Array = t.points
		var last_idx := pts.size() - 1
		if last_idx <= 0:
			continue
			
		var max_seg := last_idx 

		if t == player.trail:
			max_seg = max(0, last_idx - ignore_last_segments)
		for i in range(max_seg):
			var closest_point: Vector2 = Geometry2D.get_closest_point_to_segment(player.position, pts[i], pts[i + 1])
			if closest_point.distance_squared_to(player.position) <= player.radius_squared:
				return true
	return false


func _on_spawn_trail(new_trail: Node) -> void:
	trails.append(new_trail)

func _on_RoundStartTimer_timeout() -> void:
	print("RoundStartTimer fired")
	for p in players:
		players[p][0].set_active(true)
		players[p][0].get_node("Arrow").visible = false

func _on_RoundOverTimer_timeout() -> void:
	$UI/Control/VBoxContainer/LabelRoundOver.text = ""
	if players.size() > 0:
		start_round()

func _on_Walls_area_exited(area: Area2D) -> void:
	# Collision for player hitting the walls.
	if area.is_in_group("Player"):
		area.set_active(false)
		remaining_players -= 1
		if remaining_players <= 1:
			round_over()
			
func add_player_from_net(pid: int) -> void:
	var new_player = player_packed.instantiate()
	new_player.spawn_trail.connect(_on_spawn_trail)
	add_child(new_player)
	new_player.player_num = (pid % 4) + 1
	players[pid] = [new_player, 0]
	match new_player.player_num:
		1: $UI/Control/VBoxContainer/LabelBlue.visible = true
		2: $UI/Control/VBoxContainer/LabelOrange.visible = true
		3: $UI/Control/VBoxContainer/LabelGreen.visible = true
		4: $UI/Control/VBoxContainer/LabelPurple.visible = true


func set_input_for_pid(pid: int, left: bool, right: bool) -> void:
	if players.has(pid):
		players[pid][0].set_input(left, right)
		
func remove_player(pid:int) -> void:
	if players.has(pid):
		players[pid][0].queue_free()
		players.erase(pid)
		remaining_players = max(0, players.size())
