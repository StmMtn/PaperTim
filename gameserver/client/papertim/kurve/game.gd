
extends Node2D
class_name GameRoot
signal round_state_changed(running: bool)
signal round_finished(winner_pid: int, draw: bool)

@export var player_packed: PackedScene
@export var spawn_bounds_x: Vector2 = Vector2.ZERO
@export var spawn_bounds_y: Vector2 = Vector2.ZERO
@export var network_driven: bool = false
@export var border_thickness: float = 6.0
@export var border_color: Color = Color.DARK_RED
@export var use_viewport_bounds: bool = false
@export var arena_margin: int = 40
@export var head_radius_px: float = 7.0
@export var spawn_extra_margin: float = 60.0	# wie weit weg vom Rand spawnen

var _play_bounds_x: Vector2
var _play_bounds_y: Vector2
var name_by_pid: Dictionary = {}
var is_authority: bool = false
var players: Dictionary = {}
var trails: Array = []
var remaining_players: int
var round_running := false

const LAYER_PLAYER := 1
const LAYER_WALLS  := 1 << 1

func _ready():
	randomize()
	_ensure_ready_ui()
	_fix_ui_layout()
	if use_viewport_bounds:
		_update_bounds_from_viewport()
	_build_arena_from_bounds()
	_setup_walls()
	if network_driven: # network_driven = entscheidet ob lokal oder auf server, für Tests in Godot
		$UI/Control/VBoxContainer/ExitInstructions.visible = false
		for n in ["LabelBlue","LabelOrange","LabelGreen","LabelPurple"]:
			if $UI/Control/VBoxContainer.has_node(n):
				$UI/Control/VBoxContainer.get_node(n).visible = false
	else:
		for n in GlobalData.player_nums:
			var new_player: Area2D = player_packed.instantiate()
			_configure_player(new_player)
			new_player.spawn_trail.connect(_on_spawn_trail)
			add_child(new_player)
			new_player.player_num = n
			players[n] = [new_player, 0]
	if not network_driven:
		call_deferred("start_round")
	var rst := $RoundStartTimer
	if rst and not rst.is_connected("timeout", Callable(self, "_on_RoundStartTimer_timeout")):
		rst.timeout.connect(_on_RoundStartTimer_timeout)
	var rot := $RoundOverTimer
	if rot and not rot.is_connected("timeout", Callable(self, "_on_RoundOverTimer_timeout")):
		rot.timeout.connect(_on_RoundOverTimer_timeout)

func _update_bounds_from_viewport() -> void:
	var sz := get_viewport_rect().size
	spawn_bounds_x = Vector2(arena_margin, sz.x - arena_margin)
	spawn_bounds_y = Vector2(arena_margin, sz.y - arena_margin)

func _build_arena_from_bounds() -> void:
	var x0 := spawn_bounds_x.x
	var x1 := spawn_bounds_x.y
	var y0 := spawn_bounds_y.x
	var y1 := spawn_bounds_y.y
	var north: Line2D = $"Arena/North"
	var south: Line2D = $"Arena/South"
	var west : Line2D = $"Arena/West"
	var east : Line2D = $"Arena/East"
	for l in [north, south, west, east]:
		if l:
			l.width = border_thickness
			l.default_color = border_color
	if north: north.points = PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0)])
	if south: south.points = PackedVector2Array([Vector2(x0, y1), Vector2(x1, y1)])
	if west:  west.points  = PackedVector2Array([Vector2(x0, y0), Vector2(x0, y1)])
	if east:  east.points  = PackedVector2Array([Vector2(x1, y0), Vector2(x1, y1)])
	
	var inset := head_radius_px + border_thickness * 0.5
	var walls: Area2D = $"Arena/Walls"
	var col: CollisionShape2D = $"Arena/Walls/CollisionShape2D"
	var shape := col.shape as RectangleShape2D
	var center := Vector2((x0 + x1) * 0.5, (y0 + y1) * 0.5)
	var full_size := Vector2((x1 - x0), (y1 - y0))
	var safe_size := full_size - Vector2(2.0 * inset, 2.0 * inset)
	
	if safe_size.x < 0.0: safe_size.x = 0.0
	if safe_size.y < 0.0: safe_size.y = 0.0

	walls.position = center
	col.position = Vector2.ZERO
	if shape:
		shape.size = safe_size

	var spawn_inset := inset + spawn_extra_margin
	var sx0 := x0 + spawn_inset
	var sx1 := x1 - spawn_inset
	var sy0 := y0 + spawn_inset
	var sy1 := y1 - spawn_inset
	if sx1 < sx0: sx1 = sx0
	if sy1 < sy0: sy1 = sy0
	
	# sichere Spawn-Grenzen merken (damit nicht außerhalb gespawnt wird)
	_play_bounds_x = Vector2(x0 + inset, x1 - inset)
	_play_bounds_y = Vector2(y0 + inset, y1 - inset)

func _setup_walls() -> void:
	var walls: Area2D = $"Arena/Walls"
	walls.monitoring = true
	walls.monitorable = true
	walls.collision_layer = LAYER_WALLS
	walls.collision_mask  = LAYER_PLAYER
	var col: CollisionShape2D = $"Arena/Walls/CollisionShape2D"
	if col:
		col.disabled = false
	if not walls.is_connected("area_exited", Callable(self, "_on_Walls_area_exited")):
		walls.area_exited.connect(_on_Walls_area_exited)

func set_authority(on: bool) -> void:
	is_authority = on
	var walls := $"Arena/Walls" as Area2D
	if walls:
		walls.monitoring = (not network_driven) or is_authority

func _configure_player(p: Area2D) -> void:
	p.collision_layer = LAYER_PLAYER
	p.collision_mask  = 0
	p.monitorable = true
	if not p.is_in_group("Player"):
		p.add_to_group("Player")

func start_round() -> void:
	for t in trails: t.queue_free()
	trails.clear()

	var sx0 := _play_bounds_x.x + spawn_extra_margin
	var sx1 := _play_bounds_x.y - spawn_extra_margin
	var sy0 := _play_bounds_y.x + spawn_extra_margin
	var sy1 := _play_bounds_y.y - spawn_extra_margin
	for p in players:
		players[p][0].position = Vector2(
			randf_range(sx0, sx1),
			randf_range(sy0, sy1)
		)
		players[p][0].start() 
	
	remaining_players = players.size()
	round_running = true
	emit_signal("round_state_changed", round_running)
	$RoundStartTimer.start()

func start_round_net(spawns: Dictionary, seed: int) -> void:
	for t in trails: t.queue_free()
	trails.clear()

	for pid_str in spawns.keys():
		var pid := int(pid_str)
		if not players.has(pid):
			add_player_from_net(pid)

	for pid_str in spawns.keys():
		var pid := int(pid_str)
		var s: Dictionary = spawns[pid_str]
		var pl = players[pid][0]
		pl.position = Vector2(float(s["x"]), float(s["y"]))
		pl.start_with_angle(float(s["angle"]), true, seed + pid)
	remaining_players = players.size()
	round_running = true
	emit_signal("round_state_changed", round_running)
	$RoundStartTimer.start()

func _physics_process(_delta: float) -> void:
	var fps := $UI/Control/VBoxContainer.get_node_or_null("FPSCounter")
	if fps and fps.visible:
		fps.text = str(Engine.get_frames_per_second())
	if not network_driven or is_authority:
		for p in players:
			if player_collision(players[p][0]):
				players[p][0].set_active(false)
				remaining_players -= 1
				if remaining_players <= 1:
					round_over()

func round_over() -> void:
	var winner_pid := -1
	if remaining_players == 1:
		for p in players:
			if players[p][0].is_alive():
				winner_pid = int(p)
				players[p][1] += 1
				var human := _name_or_color_for_pid(p)
				match players[p][0].player_num:
					1: $UI/Control/VBoxContainer/LabelBlue.text   = "%s: %s" % [human, players[p][1]]
					2: $UI/Control/VBoxContainer/LabelOrange.text = "%s: %s" % [human, players[p][1]]
					3: $UI/Control/VBoxContainer/LabelGreen.text  = "%s: %s" % [human, players[p][1]]
					4: $UI/Control/VBoxContainer/LabelPurple.text = "%s: %s" % [human, players[p][1]]
				$UI/Control/VBoxContainer/LabelRoundOver.text = "%s WINS!" % human
				break
		emit_signal("round_finished", winner_pid, false)
	else:
		$UI/Control/VBoxContainer/LabelRoundOver.text = "IT'S A DRAW!"
		emit_signal("round_finished", 0, true)
	freeze_all_players()
	$RoundOverTimer.start()
	round_running = false
	emit_signal("round_state_changed", round_running)

func player_collision(player) -> bool:
	if not player.is_alive(): return false
	var ignore_last_segments := 6
	for t in trails:
		var pts: PackedVector2Array = t.points
		var last_idx := pts.size() - 1
		if last_idx <= 0: continue
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

func _on_Walls_area_exited(area: Area2D) -> void:
	if network_driven and not is_authority:
		return
	if area.is_in_group("Player"):
		if "is_alive" in area and not area.is_alive():
			return
		area.set_active(false)
		remaining_players -= 1
		if remaining_players <= 1:
			round_over()

func add_player_from_net(pid: int) -> void:
	var new_player: Area2D = player_packed.instantiate()
	if name_by_pid.has(pid):
		new_player.set_display_name(String(name_by_pid[pid]))
	_configure_player(new_player)                # <<< Layer/Mask/Group
	new_player.spawn_trail.connect(_on_spawn_trail)
	add_child(new_player)
	new_player.player_num = (pid % 4) + 1
	players[pid] = [new_player, 0]
	match new_player.player_num:
		1: $UI/Control/VBoxContainer/LabelBlue.visible = true
		2: $UI/Control/VBoxContainer/LabelOrange.visible = true
		3: $UI/Control/VBoxContainer/LabelGreen.visible = true
		4: $UI/Control/VBoxContainer/LabelPurple.visible = true
	if round_running:
		new_player.position = Vector2(
			randf_range(spawn_bounds_x.x, spawn_bounds_x.y),
			randf_range(spawn_bounds_y.x, spawn_bounds_y.y)
		)
		new_player.start()
		new_player.set_active(true)
		new_player.get_node("Arrow").visible = false
		remaining_players = players.size()
	_refresh_score_labels()

func set_input_for_pid(pid: int, left: bool, right: bool) -> void:
	if players.has(pid):
		players[pid][0].set_input(left, right)

func remove_player(pid:int) -> void:
	if players.has(pid):
		players[pid][0].queue_free()
		players.erase(pid)
		remaining_players = max(0, players.size())

func update_ready_ui(my_id: int, host_id: int, ids: Array, ready_by_pid: Dictionary, my_ready: bool) -> void:
	var root := $UI/Control
	var card := root.find_child("ReadyCard", true, false) as PanelContainer
	if card == null:
		return
	var margin := card.get_node_or_null("Margin")
	if margin == null:
		return
	var body := margin.get_node_or_null("Body") as VBoxContainer
	if body == null:
		return
	var you_lbl := body.get_node_or_null("YouLabel") as Label
	var btn := body.get_node_or_null("ReadyButton") as CheckButton
	var list := body.get_node_or_null("ReadyList") as VBoxContainer
	if you_lbl and players.has(my_id):
		var human_me := _name_or_color_for_pid(my_id)
		var host_tag := " (HOST)" if my_id == host_id else ""
		you_lbl.text = "You: %s%s" % [human_me, host_tag]
	if btn and btn.has_method("set_pressed_no_signal"):
		btn.set_pressed_no_signal(my_ready)
	if list:
		for c in list.get_children(): c.queue_free()
		for pid in ids:
			var is_me: bool = (pid == my_id)
			var r: bool = bool(ready_by_pid.get(pid, false))
			var who: String = _name_or_color_for_pid(pid)
			var me_tag: String = " (you)" if is_me else ""
			var state: String = "READY" if r else "waiting..."
			var line := Label.new()
			line.text = "%s%s — %s" % [who, me_tag, state]
			var font_col: Color = Color(0.6, 1.0, 0.6) if r else Color(0.85, 0.85, 0.85)
			line.add_theme_color_override("font_color", font_col)
			list.add_child(line)
	card.visible = not round_running

func _color_name_for(n: int) -> String:
	match n:
		1: return "BLUE"
		2: return "ORANGE"
		3: return "GREEN"
		4: return "PURPLE"
		_: return "?"
		
func _ensure_ready_ui() -> void:
	var root := $UI/Control
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	root.set_anchors_preset(Control.PRESET_FULL_RECT, true)
	root.set_offsets_preset(Control.PRESET_FULL_RECT)
	root.z_index = 100
	var overlay := root.get_node_or_null("ReadyOverlay") as CenterContainer
	if overlay == null:
		overlay = CenterContainer.new()
		overlay.name = "ReadyOverlay"
		root.add_child(overlay)
		overlay.set_anchors_preset(Control.PRESET_FULL_RECT, true)
		overlay.set_offsets_preset(Control.PRESET_FULL_RECT)
		overlay.mouse_filter = Control.MOUSE_FILTER_STOP
		overlay.z_index = 200
	var card := overlay.get_node_or_null("ReadyCard") as PanelContainer
	if card == null:
		card = PanelContainer.new()
		card.name = "ReadyCard"
		overlay.add_child(card)
		card.custom_minimum_size = Vector2(340, 0)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.add_theme_color_override("panel", Color(0, 0, 0, 0.35)) # dunkles, leicht transparentes Panel
		card.set_anchors_preset(Control.PRESET_CENTER, false)
		var margin := MarginContainer.new()
		margin.name = "Margin"
		card.add_child(margin)
		margin.add_theme_constant_override("margin_left", 12)
		margin.add_theme_constant_override("margin_top", 12)
		margin.add_theme_constant_override("margin_right", 12)
		margin.add_theme_constant_override("margin_bottom", 12)
		var body := VBoxContainer.new()
		body.name = "Body"
		margin.add_child(body)
		body.add_theme_constant_override("separation", 8)
		var you := Label.new()
		you.name = "YouLabel"
		you.text = "You: ?"
		you.add_theme_font_size_override("font_size", 16)
		body.add_child(you)
		var btn := CheckButton.new()
		btn.name = "ReadyButton"
		btn.text = "Ready (R)"
		btn.toggle_mode = true
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.focus_mode = Control.FOCUS_ALL
		body.add_child(btn)
		var list := VBoxContainer.new()
		list.name = "ReadyList"
		list.custom_minimum_size = Vector2(0, 120)
		list.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		body.add_child(list)
	var vbox := root.get_node_or_null("VBoxContainer")
	if vbox:
		var old_btn := vbox.get_node_or_null("ReadyButton")
		if old_btn: old_btn.queue_free()
		var old_panel := vbox.get_node_or_null("ReadyPanel")
		if old_panel: old_panel.queue_free()

func _fix_ui_layout() -> void:
	var root := $UI/Control
	root.set_anchors_preset(Control.PRESET_FULL_RECT, true)
	root.set_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	root.z_index = 100
	var overlay := root.get_node_or_null("ReadyOverlay") as CenterContainer
	if overlay:
		overlay.z_index = 200
		overlay.mouse_filter = Control.MOUSE_FILTER_STOP

func get_arena_rect() -> Dictionary:
	return {
		"x0": spawn_bounds_x.x,
		"x1": spawn_bounds_x.y,
		"y0": spawn_bounds_y.x,
		"y1": spawn_bounds_y.y
	}

func set_arena_from_host(ar: Dictionary) -> void:
	spawn_bounds_x = Vector2(float(ar.get("x0", 0.0)), float(ar.get("x1", 0.0)))
	spawn_bounds_y = Vector2(float(ar.get("y0", 0.0)), float(ar.get("y1", 0.0)))
	_build_arena_from_bounds()
	
func set_name_for_pid(pid: int, name: String) -> void:
	name_by_pid[pid] = name
	if players.has(pid):
		var pl: Area2D = players[pid][0]
		if "set_display_name" in pl:
			pl.set_display_name(name)
	if has_method("update_ready_ui"):
		var ids := players.keys()
		update_ready_ui(-1, -1, ids, {}, false)
	_refresh_score_labels()

		
func _name_or_color_for_pid(pid: int) -> String:
	if name_by_pid.has(pid) and String(name_by_pid[pid]) != "":
		return String(name_by_pid[pid])
	if players.has(pid):
		return _color_name_for(players[pid][0].player_num)
	return "?"
	
func _refresh_score_labels() -> void:
	var map := {
		1: $UI/Control/VBoxContainer/LabelBlue,
		2: $UI/Control/VBoxContainer/LabelOrange,
		3: $UI/Control/VBoxContainer/LabelGreen,
		4: $UI/Control/VBoxContainer/LabelPurple,
	}
	for pid in players.keys():
		var pnode = players[pid][0]
		var score = players[pid][1]
		var human = _name_or_color_for_pid(pid)
		var lbl: Label = map.get(pnode.player_num, null)
		if lbl:
			lbl.text = "%s: %s" % [human, score]
			
func apply_remote_round_over(winner_pid: int, draw: bool) -> void:
	freeze_all_players()
	$RoundOverTimer.start()
	round_running = false
	emit_signal("round_state_changed", round_running)
	if not draw and players.has(winner_pid):
		players[winner_pid][1] += 1
		var human := _name_or_color_for_pid(winner_pid)
		match players[winner_pid][0].player_num:
			1: $UI/Control/VBoxContainer/LabelBlue.text   = "%s: %s" % [human, players[winner_pid][1]]
			2: $UI/Control/VBoxContainer/LabelOrange.text = "%s: %s" % [human, players[winner_pid][1]]
			3: $UI/Control/VBoxContainer/LabelGreen.text  = "%s: %s" % [human, players[winner_pid][1]]
			4: $UI/Control/VBoxContainer/LabelPurple.text = "%s: %s" % [human, players[winner_pid][1]]
		$UI/Control/VBoxContainer/LabelRoundOver.text = "%s WINS!" % human
	else:
		$UI/Control/VBoxContainer/LabelRoundOver.text = "IT'S A DRAW!"
	emit_signal("round_finished", winner_pid, draw)

func freeze_all_players() -> void:
	for pid in players.keys():
		var p = players[pid][0]
		p.set_active(false)
		p.set_input(false, false)

func _on_RoundStartTimer_timeout() -> void:
	for pid in players.keys():
		var pl: Area2D = players[pid][0]
		pl.set_active(true)
		var arrow := pl.get_node_or_null("Arrow")
		if arrow: arrow.visible = false

func _on_RoundOverTimer_timeout() -> void:
	$UI/Control/VBoxContainer/LabelRoundOver.text = ""
	if not network_driven:
		start_round()
