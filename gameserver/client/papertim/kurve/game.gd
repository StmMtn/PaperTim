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

@export var head_radius_px: float = 7.0         # dein echter Kopf-Radius
@export var spawn_extra_margin: float = 60.0    # wie weit weg vom Rand spawnen

var _play_bounds_x: Vector2
var _play_bounds_y: Vector2

# --- Layer-Definitionen (Bits): 1 => 1<<0, 2 => 1<<1
const LAYER_PLAYER := 1        # Bit 1
const LAYER_WALLS  := 1 << 1   # Bit 2

var players: Dictionary = {}   # pid -> [player_node, score]
var trails: Array = []
var remaining_players: int
var round_running := false

func _ready():
	randomize()
	_ensure_ready_ui()
	_fix_ui_layout()
	if use_viewport_bounds:
		_update_bounds_from_viewport()

	_build_arena_from_bounds()
	_setup_walls()               # <<< Walls konfigurieren & Signal verbinden

	if network_driven:
		$UI/Control/VBoxContainer/ExitInstructions.visible = false
		for n in ["LabelBlue","LabelOrange","LabelGreen","LabelPurple"]:
			if $UI/Control/VBoxContainer.has_node(n):
				$UI/Control/VBoxContainer.get_node(n).visible = false
	else:
		# Lokaler Modus (Main Menu → GlobalData.player_nums)
		for n in GlobalData.player_nums:
			var new_player: Area2D = player_packed.instantiate()
			_configure_player(new_player)                        # <<< Layer/Mask/Group
			new_player.spawn_trail.connect(_on_spawn_trail)
			add_child(new_player)
			new_player.player_num = n
			players[n] = [new_player, 0]

	if not network_driven:
		call_deferred("start_round")


func _update_bounds_from_viewport() -> void:
	var sz := get_viewport_rect().size
	spawn_bounds_x = Vector2(arena_margin, sz.x - arena_margin)
	spawn_bounds_y = Vector2(arena_margin, sz.y - arena_margin)


func _build_arena_from_bounds() -> void:
	var x0 := spawn_bounds_x.x
	var x1 := spawn_bounds_x.y
	var y0 := spawn_bounds_y.x
	var y1 := spawn_bounds_y.y

	# --- Linien (nur Visual) unverändert ---
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

	# --- Spielbare Innenfläche ("Walls") schrumpfen um Radius + halbe Linienbreite ---
	var inset := head_radius_px + border_thickness * 0.5

	var walls: Area2D = $"Arena/Walls"
	var col: CollisionShape2D = $"Arena/Walls/CollisionShape2D"
	var shape := col.shape as RectangleShape2D

	var center := Vector2((x0 + x1) * 0.5, (y0 + y1) * 0.5)
	var full_size := Vector2((x1 - x0), (y1 - y0))
	var safe_size := full_size - Vector2(2.0 * inset, 2.0 * inset)
	if safe_size.x < 0.0: safe_size.x = 0.0
	if safe_size.y < 0.0: safe_size.y = 0.0

	walls.position = center            # Shape bleibt relativ bei (0,0)
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
	
	# Optional: sichere Spawn-Grenzen merken (damit nicht im Todesband gespawnt wird)
	_play_bounds_x = Vector2(x0 + inset, x1 - inset)
	_play_bounds_y = Vector2(y0 + inset, y1 - inset)

func _setup_walls() -> void:
	var walls: Area2D = $"Arena/Walls"
	# Kollision & Überwachung
	walls.monitoring = true
	walls.monitorable = true
	walls.collision_layer = LAYER_WALLS
	walls.collision_mask  = LAYER_PLAYER   # Walls "sieht" Spieler auf Layer 1

	# Falls im Editor deaktiviert wurde:
	var col: CollisionShape2D = $"Arena/Walls/CollisionShape2D"
	if col:
		col.disabled = false

	# Signal per Code verbinden (einmalig)
	if not walls.is_connected("area_exited", Callable(self, "_on_Walls_area_exited")):
		walls.area_exited.connect(_on_Walls_area_exited)
	# (Optional) zum Debuggen:
	# if not walls.is_connected("area_entered", Callable(self, "_on_Walls_area_entered")):
	# 	walls.area_entered.connect(_on_Walls_area_entered)


func _configure_player(p: Area2D) -> void:
	# Player soll von Walls erkannt werden, selbst aber nichts erkennen müssen
	p.collision_layer = LAYER_PLAYER
	p.collision_mask  = 0
	p.monitorable = true
	# Gruppe, falls nicht schon im Player-Skript:
	if not p.is_in_group("Player"):
		p.add_to_group("Player")


func _notification(what):
	if what == NOTIFICATION_WM_SIZE_CHANGED and use_viewport_bounds:
		_update_bounds_from_viewport()
		_build_arena_from_bounds()


func start_round() -> void:
	for t in trails: t.queue_free()
	trails.clear()

	#for p in players:
		#players[p][0].position = Vector2(
			#randf_range(spawn_bounds_x.x, spawn_bounds_x.y),
			#randf_range(spawn_bounds_y.x, spawn_bounds_y.y) OKE
		#)
		#players[p][0].start()
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


func _process(_delta: float) -> void:
	var fps := $UI/Control/VBoxContainer.get_node_or_null("FPSCounter")
	if fps and fps.visible:
		fps.text = str(Engine.get_frames_per_second())

	# Trail-Kollisionen (eigene Logik)
	for p in players:
		if player_collision(players[p][0]):
			players[p][0].set_active(false)
			remaining_players -= 1
			if remaining_players <= 1:
				round_over()

	if Input.is_action_just_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://kurve/main_menu.tscn")


func round_over() -> void:
	$RoundOverTimer.start()
	round_running = false
	emit_signal("round_state_changed", round_running)
	if remaining_players == 1:
		var winner_pid := -1
		for p in players:
			if players[p][0].is_alive():
				winner_pid = int(p)
				players[p][0].set_active(false)
				players[p][1] += 1
				match players[p][0].player_num:
					1:
						$UI/Control/VBoxContainer/LabelBlue.text   = "BLUE: %s"   % players[p][1]
						$UI/Control/VBoxContainer/LabelRoundOver.text = "BLUE WINS!"
					2:
						$UI/Control/VBoxContainer/LabelOrange.text = "ORANGE: %s" % players[p][1]
						$UI/Control/VBoxContainer/LabelRoundOver.text = "ORANGE WINS!"
					3:
						$UI/Control/VBoxContainer/LabelGreen.text  = "GREEN: %s"  % players[p][1]
						$UI/Control/VBoxContainer/LabelRoundOver.text = "GREEN WINS!"
					4:
						$UI/Control/VBoxContainer/LabelPurple.text = "PURPLE: %s" % players[p][1]
						$UI/Control/VBoxContainer/LabelRoundOver.text = "PURPLE WINS!"
				break
		emit_signal("round_finished", winner_pid, false)

	else:
		$UI/Control/VBoxContainer/LabelRoundOver.text = "IT'S A DRAW!"
		emit_signal("round_finished", 0, true)


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


func _on_RoundStartTimer_timeout() -> void:
	for p in players:
		players[p][0].set_active(true)
		players[p][0].get_node("Arrow").visible = false


func _on_RoundOverTimer_timeout() -> void:
	$UI/Control/VBoxContainer/LabelRoundOver.text = ""
	#if players.size() > 0:
		#if network_driven:
			#get_parent().call_deferred("_host_request_next_round")
		#else:
			#start_round()
	if not network_driven:
		start_round()  # Lokalmodus darf direkt starten

# --- WICHTIGER Handler: Spieler verlässt die Arena-Fläche
func _on_Walls_area_exited(area: Area2D) -> void:
	if area.is_in_group("Player"):
		area.set_active(false)
		remaining_players -= 1
		if remaining_players <= 1:
			round_over()

# Debug optional:
# func _on_Walls_area_entered(area: Area2D) -> void:
# 	print("ENTER:", area)


func add_player_from_net(pid: int) -> void:
	var new_player: Area2D = player_packed.instantiate()
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


func set_input_for_pid(pid: int, left: bool, right: bool) -> void:
	if players.has(pid):
		players[pid][0].set_input(left, right)


func remove_player(pid:int) -> void:
	if players.has(pid):
		players[pid][0].queue_free()
		players.erase(pid)
		remaining_players = max(0, players.size())
		
# In game.gd hinzufügen

func update_ready_ui(my_id: int, host_id: int, ids: Array, ready_by_pid: Dictionary, my_ready: bool) -> void:
	var card := $UI/Control.get_node_or_null("ReadyCard") as PanelContainer
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

	# eigene Farbe/Host
	if you_lbl and players.has(my_id):
		var color_name := _color_name_for(players[my_id][0].player_num)
		var host_tag := " (HOST)" if my_id == host_id else ""
		you_lbl.text = "You: %s%s" % [color_name, host_tag]

	# Button-Status spiegeln
	if btn and btn.has_method("set_pressed_no_signal"):
		btn.set_pressed_no_signal(my_ready)

	# Liste bauen
	if list:
		for c in list.get_children(): c.queue_free()
		for pid in ids:
			var is_me: bool = (pid == my_id)
			var r: bool = bool(ready_by_pid.get(pid, false))
			var colname: String = _color_name_for(players[pid][0].player_num) if players.has(pid) else "?"
			var me_tag: String = " (you)" if is_me else ""
			var state: String = "READY" if r else "waiting..."

			var line := Label.new()
			line.text = "%s%s — %s" % [colname, me_tag, state]
			var font_col: Color = Color(0.6, 1.0, 0.6) if r else Color(0.85, 0.85, 0.85)
			line.add_theme_color_override("font_color", font_col)
			list.add_child(line)


	# Card nur zeigen, wenn keine Runde läuft
	card.visible = not round_running

func _color_name_for(n: int) -> String:
	match n:
		1: return "BLUE"
		2: return "ORANGE"
		3: return "GREEN"
		4: return "PURPLE"
		_: return "?"
func _ensure_ready_ui() -> void:
	var root := $UI/Control                                # füllt den Screen
	# Root darf Maus durchlassen, Card fängt sie ab:
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	root.set_anchors_preset(Control.PRESET_FULL_RECT, true)
	root.set_offsets_preset(Control.PRESET_FULL_RECT)
	root.z_index = 100

	# Panel oben links: "ReadyCard"
	var card := root.get_node_or_null("ReadyCard") as PanelContainer
	if card == null:
		card = PanelContainer.new()
		card.name = "ReadyCard"
		root.add_child(card)

		# Position & Größe (oben links, schön klein)
		card.position = Vector2(12, 12)
		card.custom_minimum_size = Vector2(280, 0)
		card.mouse_filter = Control.MOUSE_FILTER_STOP   # fängt Klicks ab
		card.z_index = 200

		# Innen: Margin -> VBox(Body)
		var margin := MarginContainer.new()
		margin.name = "Margin"
		card.add_child(margin)
		margin.add_theme_constant_override("margin_left",  8)
		margin.add_theme_constant_override("margin_top",   8)
		margin.add_theme_constant_override("margin_right", 8)
		margin.add_theme_constant_override("margin_bottom",8)

		var body := VBoxContainer.new()
		body.name = "Body"
		margin.add_child(body)
		body.add_theme_constant_override("separation", 6)

		# Zeile: "You: …"
		var you := Label.new()
		you.name = "YouLabel"
		you.text = "You: ?"
		body.add_child(you)

		# Ready-Button
		var btn := CheckButton.new()
		btn.name = "ReadyButton"
		btn.text = "Ready (R)"
		btn.toggle_mode = true
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.focus_mode = Control.FOCUS_ALL
		body.add_child(btn)

		# Liste der Spieler
		var list := VBoxContainer.new()
		list.name = "ReadyList"
		list.custom_minimum_size = Vector2(0, 100)     # genug Höhe
		list.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		body.add_child(list)
		
		# --- Legacy-UI aufräumen: alles unter VBoxContainer, was "Ready..." heißt, entfernen
		var vbox := $UI/Control.get_node_or_null("VBoxContainer")
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

	# nur die Card richtig „oben“ halten & klickbar
	var card := root.get_node_or_null("ReadyCard") as PanelContainer
	if card:
		card.z_index = 200
		card.mouse_filter = Control.MOUSE_FILTER_STOP
	# in _ensure_ready_ui(), nachdem du card angelegt hast:
	card.add_theme_color_override("panel", Color(0, 0, 0, 0.35))
func _enter_tree() -> void:
	# reagiert zuverlässig (auch im Web) auf Fullscreen/Resize
	get_viewport().size_changed.connect(_on_viewport_resized)

func _on_viewport_resized() -> void:
	# Nur dann neu berechnen:
	# - wenn wir Viewport-Bounds benutzen
	# - und NICHT gerade eine Net-Runde läuft (sonst Desync)
	if use_viewport_bounds and (not network_driven or not round_running):
		_update_bounds_from_viewport()
		_build_arena_from_bounds()

# Host gibt die aktuell verwendete Arena zurück
func get_arena_rect() -> Dictionary:
	return {
		"x0": spawn_bounds_x.x,
		"x1": spawn_bounds_x.y,
		"y0": spawn_bounds_y.x,
		"y1": spawn_bounds_y.y
	}

# Client setzt Arena exakt auf Host-Werte
func set_arena_from_host(ar: Dictionary) -> void:
	spawn_bounds_x = Vector2(float(ar.get("x0", 0.0)), float(ar.get("x1", 0.0)))
	spawn_bounds_y = Vector2(float(ar.get("y0", 0.0)), float(ar.get("y1", 0.0)))
	_build_arena_from_bounds()
