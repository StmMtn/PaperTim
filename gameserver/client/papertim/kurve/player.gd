extends Area2D
signal spawn_trail(new_trail)
var rng := RandomNumberGenerator.new()
var use_rng := false
var steer_left: bool = false
var steer_right: bool = false
var next_gap_in := 0.0
var gap_len := 0.0
var line_timer: float = 0.0
var gap_timer: float = 0.0
var forward: Vector2 = Vector2.UP
var drawing_line: bool = true
var trail: Line2D
var display_name: String = ""
var custom_color: Color = Color(0, 0, 0, 0) # wenn a>0, überschreibt Farb-Mapping
var name_label: Label
var active: bool = false

@export var use_local_input := false
@export var player_packed: PackedScene
@export var player_num: int = 1
@export var speed: float = 25.0
@export var rotate_speed: float = 12.5
@export var place_point_distance: float = 5.0
@export var line_time_limits: Vector2 = Vector2(1.6, 6)
@export var gap_length_limits: Vector2 = Vector2(0.5, 2)
@export var trail_packed: PackedScene
@onready var sprite: Sprite2D = $Sprite
@onready var radius_squared: float = pow(($CollisionShape2D.shape as CircleShape2D).radius, 2)
@export var max_trail_seconds: float = 8.0  # so lange „lebt“ der sichtbare Trail

func set_input(left: bool, right: bool) -> void:
	steer_left = left
	steer_right = right
	
func _ready():
	randomize()
	add_to_group("Player") 
	$Arrow.modulate = get_player_color()
	set_physics_process(true)

func set_display_name(n: String) -> void:
	display_name = n
	_ensure_name_label()
	name_label.text = n

func set_player_color(c: Color) -> void:
	custom_color = c
	$Arrow.modulate = get_player_color()
	if trail:
		trail.default_color = get_player_color()

func _ensure_name_label() -> void:
	if name_label: return
	name_label = Label.new()
	name_label.name = "NameLabel"
	name_label.text = display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	name_label.position = Vector2(0, -18)
	name_label.modulate = Color(1, 1, 1, 0.9)
	name_label.add_theme_font_size_override("font_size", 12)
	add_child(name_label)

func start():
	line_timer = 0.0
	gap_timer = 0.0
	drawing_line = true
	var angle = randf_range(0.0, 2.0 * PI)
	forward = Vector2(cos(angle), sin(angle))
	$Arrow.visible = true
	$Arrow.rotation = angle + PI / 2.0
	use_rng = false
	_reset_gap_schedule()
	add_new_trail()
	$Arrow.modulate = get_player_color()
	set_active(false)

func set_active(on: bool) -> void:
	active = on
	$Arrow.visible = on
	set_physics_process(on)

func is_alive() -> bool:
	return active

func _process(_delta):
	if use_local_input:
		var left  = Input.is_action_pressed("p%s_left" % player_num)
		var right = Input.is_action_pressed("p%s_right" % player_num)
		set_input(left, right)

func _physics_process(delta):
	if not active:
		return
	var turn := 0.0
	if steer_left:  turn -= 1.0
	if steer_right: turn += 1.0
	if turn != 0.0:
		forward = forward.rotated(rotate_speed * turn * delta)
	position += forward * speed * delta
	if drawing_line:
		line_timer += delta
		if trail:
			var need_point := trail.points.size() == 0
			if not need_point and position.distance_to(trail.points[-1]) > place_point_distance:
				need_point = true
			if need_point:
				add_new_point()
		if line_timer >= next_gap_in:
			line_timer = 0.0
			drawing_line = false
	else:
		gap_timer += delta
		if gap_timer >= gap_len:
			gap_timer = 0.0
			drawing_line = true
			add_new_trail()
			_reset_gap_schedule() 

func add_new_trail():
	trail = trail_packed.instantiate()
	get_parent().call_deferred("add_child", trail)
	trail.default_color = get_player_color()
	if "max_length_px" in trail:
		trail.max_length_px = max_trail_seconds * speed
	spawn_trail.emit(trail)
	add_new_point()

func add_new_point():
	var spawn_pos: Vector2 = position - forward * 7.0
	var pts: PackedVector2Array = trail.points
	pts.append(spawn_pos)
	trail.points = pts

func get_player_color():
	if custom_color.a > 0.0:
		return custom_color
	if player_num == 1: return Color.DEEP_SKY_BLUE
	elif player_num == 2: return Color.CORAL
	elif player_num == 3: return Color.GREEN_YELLOW
	else: return Color.MEDIUM_ORCHID
	
func start_with_angle(angle: float, network_mode: bool, seed: int) -> void:
	line_timer = 0.0
	gap_timer = 0.0
	drawing_line = true
	forward = Vector2(cos(angle), sin(angle))
	$Arrow.visible = true
	$Arrow.rotation = angle + PI / 2.0
	use_rng = network_mode
	if network_mode:
		rng.seed = seed
	_reset_gap_schedule()
	add_new_trail()
	$Arrow.modulate = get_player_color()
	set_active(false)
	
func _reset_gap_schedule() -> void:
	if use_rng:
		next_gap_in = rng.randf_range(line_time_limits.x, line_time_limits.y)   # Dauer „zeichnen“
		gap_len     = rng.randf_range(gap_length_limits.x, gap_length_limits.y) # Dauer „Lücke“
	else:
		next_gap_in = randf_range(line_time_limits.x, line_time_limits.y)
		gap_len     = randf_range(gap_length_limits.x, gap_length_limits.y)
