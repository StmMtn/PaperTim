extends Area2D
signal spawn_trail(new_trail)

# --- NET-ENTKOPPLUNG ---
var steer_left: bool = false
var steer_right: bool = false

func set_input(left: bool, right: bool) -> void:
	steer_left = left
	steer_right = right

@export var use_local_input := false

# --- PARAMS ---
@export var player_packed: PackedScene
@export var player_num: int = 1
@export var speed: float = 25.0
@export var rotate_speed: float = 12.5
@export var place_point_distance: float = 5.0
@export var line_time_limits: Vector2 = Vector2(1.6, 6)
@export var gap_time_limit: float = 0.5
@export var trail_packed: PackedScene
@onready var sprite: Sprite2D = $Sprite
@onready var radius_squared: float = pow(($CollisionShape2D.shape as CircleShape2D).radius, 2)
@export var max_trail_seconds: float = 8.0  # so lange „lebt“ der sichtbare Trail



var current_line_limit: float = 5.0
var line_timer: float = 0.0
var gap_timer: float = 0.0
var forward: Vector2 = Vector2.UP
var drawing_line: bool = true
var trail: Line2D

# NEU: Aktiv-Flag (steuert auch _physics_process)
var active: bool = false

func _ready():
	randomize()
	add_to_group("Player") 
	$Arrow.modulate = get_player_color()
	set_physics_process(true) # wir laufen grundsätzlich in Physics

func start():
	# Startwerte je Runde
	line_timer = 0.0
	gap_timer = 0.0
	drawing_line = true
	var angle = randf_range(0.0, 2.0 * PI)
	forward = Vector2(cos(angle), sin(angle))
	$Arrow.visible = true
	$Arrow.rotation = angle + PI / 2.0
	add_new_trail()
	set_active(false)

# NEU: sauber aktivieren/deaktivieren
func set_active(on: bool) -> void:
	active = on
	$Arrow.visible = on
	set_physics_process(on)

func is_alive() -> bool:
	return active

# Nur für DEV-Tests ohne Netzwerk:
func _process(_delta):
	if use_local_input:
		var left  = Input.is_action_pressed("p%s_left" % player_num)
		var right = Input.is_action_pressed("p%s_right" % player_num)
		set_input(left, right)

func _physics_process(delta):
	if not active:
		return

	# --- Rotation & Movement über Flags ---
	var turn := 0.0
	if steer_left:  turn -= 1.0
	if steer_right: turn += 1.0
	if turn != 0.0:
		forward = forward.rotated(rotate_speed * turn * delta)

	position += forward * speed * delta

	# --- Trail / Gaps ---
	if drawing_line:
		line_timer += delta
		if trail:
			var need_point := trail.points.size() == 0
			if not need_point and position.distance_to(trail.points[-1]) > place_point_distance:
				need_point = true
			if need_point:
				add_new_point()

		if line_timer >= current_line_limit:
			line_timer = 0.0
			drawing_line = false
	else:
		gap_timer += delta
		if gap_timer >= gap_time_limit:
			gap_timer = 0.0
			drawing_line = true
			add_new_trail()

func add_new_trail():
	current_line_limit = randf_range(line_time_limits.x, line_time_limits.y)
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
	if player_num == 1: return Color.DEEP_SKY_BLUE
	elif player_num == 2: return Color.CORAL
	elif player_num == 3: return Color.GREEN_YELLOW
	else: return Color.MEDIUM_ORCHID
