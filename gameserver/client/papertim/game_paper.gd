extends Node2D

var ws := WebSocketPeer.new()
var my_id := 0
var players := {}
var http: HTTPRequest
var ws_url := ""
var auth_token := ""
var me := {}  # user info

var dev_offline := false

@onready var reconnect_timer := Timer.new()

var game: GameRoot
var known_pids: Dictionary = {}   # { pid: true }
var host_id := 0                  # kleinste PID im Room = Host#

var my_ready := false
var ready_by_pid: Dictionary = {}   # pid -> bool

# Input-Modus
var use_input_netmode := true
var last_left := false
var last_right := false

const MIN_PLAYERS_TO_START := 2   # später 2, wenn gewollt
const PLAYER_SCENE := preload("res://kurve/player.tscn")


func _ready():
	reconnect_timer.one_shot = true
	add_child(reconnect_timer)
	reconnect_timer.timeout.connect(_connect_ws)

	if dev_offline:
		_connect_ws()
		return

	http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_request_completed)

	# Token aus URL-Query ziehen (nur im Browser verfügbar)
	if Engine.has_singleton("JavaScriptBridge"):
		var search = JavaScriptBridge.eval("window.location.search")  # z.B. "?token=abc123"
		if search.begins_with("?"):
			var query = search.substr(1, search.length())  # "token=abc123"
			for part in query.split("&"):
				var kv = part.split("=")
				if kv.size() == 2 and kv[0] == "token":
					auth_token = kv[1]
					print("Auth token aus URL: %s" % auth_token)

	var base_url := ""
	if Engine.has_singleton("JavaScriptBridge"):
		base_url = JavaScriptBridge.eval("window.location.origin")
	else:
		base_url = "http://localhost:8443"
		
	# if Engine.has_singleton("JavaScriptBridge") and OS.has_feature("web"):
	#	var origin = JavaScriptBridge.eval("window?.location?.origin ?? ''")
	#	if origin is String and origin != "":
	#		base_url = origin

	http.set_meta("last_tag", "config")
	var err = http.request(base_url + "/config")
	if err != OK:
		push_error("Config-Request konnte nicht gestartet werden: %s" % str(err))
		_connect_with_fallback()


func _on_config_response(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		push_error("Config konnte nicht geladen werden (result=%s, code=%s)" % [str(result), str(code)])
		_connect_with_fallback()
		return

	var data: Dictionary = JSON.parse_string(body.get_string_from_utf8())
	if data == null or not data.has("ws_url"):
		push_error("Config-JSON ungültig")
		_connect_with_fallback()
		return

	# Testbuttons
	var btn_trophy = Button.new()
	btn_trophy.text = "Add Trophy"
	btn_trophy.pressed.connect(func(): increase_trophy())
	add_child(btn_trophy)

	var btn_games = Button.new()
	btn_games.text = "Add Game"
	btn_games.pressed.connect(func(): increase_games())
	add_child(btn_games)

func _on_config_response_fallback(body_text: String) -> void:
	# Fallback falls config nicht lief
	ws_url = "ws://localhost:8443"
	_connect_ws()

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	var tag = http.get_meta("last_tag", "")
	var text = body.get_string_from_utf8()
	if response_code >= 200 and response_code < 300:
		var jr = JSON.parse_string(text)
		if jr.error != OK:
			push_error("JSON parse error: %s" % str(jr.error))
			return
		var parsed = jr.result
 
		match tag:
			"config":
				if parsed == null or not parsed.has("ws_url"):
					push_error("Config-JSON ungültig: %s" % text)
					_connect_with_fallback()
					return
				ws_url = parsed["ws_url"]
				_connect_ws()

			"login", "register":
				auth_token = parsed.get("token", "")
				me = parsed.get("user", {})
				print("Logged in: %s" % str(me))

			"inc_trophy":
				print("Trophies now: %s" % str(parsed))

			"inc_games":
				print("Games now: %s" % str(parsed))

			_:
				print("HTTP %s -> %s" % [tag, text])
	else:
		# Fehlerstatus
		push_error("Request failed (tag=%s, code=%s): %s" % [tag, response_code, text])

func _connect_with_fallback():
	ws_url = "ws://localhost:8443"
	_connect_ws()

func _connect_ws():
	if dev_offline:
		if game == null:
			var game_packed = load("res://kurve/game.tscn")
			game = game_packed.instantiate()
			game.network_driven = true
			add_child(game)
			game.round_state_changed.connect(func(_running: bool) -> void:
				_update_ready_ui()
			)
			_wire_ready_button()   # <— UI-Button verbinden (optional)
			_update_ready_ui()     # <— erste Anzeige
		my_id = 1
		game.add_player_from_net(my_id)
		if not game.round_running:
			game.start_round()
		return

	# --- Online ---
	if game == null:
		var game_packed2 = load("res://kurve/game.tscn")
		game = game_packed2.instantiate()
		game.network_driven = true
		add_child(game)
		game.round_state_changed.connect(func(_running: bool) -> void:
			_update_ready_ui()
		)
		_wire_ready_button()   # <— UI-Button verbinden (optional)
		_update_ready_ui()     # <— erste Anzeige

	# Room-ID anhängen (vor connect)
	if Engine.has_singleton("JavaScriptBridge") and OS.has_feature("web"):
		var room: String = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('room') || ''")
		if room is String and room != "":
			var sep = "?" if not ("?" in ws_url) else "&"
			ws_url += sep + "room=" + room

	ws = WebSocketPeer.new()
	var err = ws.connect_to_url(ws_url)
	if err != OK:
		push_error("WS-Verbindung fehlgeschlagen: %s" % str(err))
		
func _process(_dt):
	if dev_offline: return
	ws.poll()
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		while ws.get_available_packet_count() > 0:
			var pkt := ws.get_packet().get_string_from_utf8()
			var data: Dictionary = JSON.parse_string(pkt)
			if data == null: continue

			match data.type:
				"init":
					my_id = int(data.id)
					known_pids[my_id] = true
					ready_by_pid[my_id] = false
					game.add_player_from_net(my_id)
					_recalc_host()
					_update_ready_ui()
				"roster":
					for id in data.ids:
						var pid := int(id)
						if not known_pids.has(pid):
							known_pids[pid] = true
							ready_by_pid[pid] = false
							game.add_player_from_net(pid)
					_recalc_host()
					_update_ready_ui()
				"ready_state":
					# initiale Ready-Liste nach Join
					for id in data.ids:
						var pid := int(id)
						ready_by_pid[pid] = true
					_update_ready_ui()
					_check_all_ready_and_start()
				"ready":
					var pid := int(data.id)
					ready_by_pid[pid] = bool(data.ready)
					_update_ready_ui()
					_check_all_ready_and_start()
				"join":
					var pid := int(data.id)
					if not known_pids.has(pid):
						known_pids[pid] = true
						ready_by_pid[pid] = false
						game.add_player_from_net(pid)
					_recalc_host()
					_update_ready_ui()
				"remove":
					var rid := int(data.id)
					game.remove_player(rid)
					if known_pids.has(rid):
						known_pids.erase(rid)
					if ready_by_pid.has(rid):
						ready_by_pid.erase(rid)
					_recalc_host()
					_update_ready_ui()
					if game.round_running and game.players.size() <= 1:
						game.round_over()
				"round_start":
					if game and data.has("arena"): # erst Arena vom Host setzen (damit alle gleich sind)
						game.set_arena_from_host(data.arena)
					# nach Start alle wieder un-ready setzen (für nächste Runde)
					for pid in ready_by_pid.keys():
						ready_by_pid[pid] = false
					my_ready = false
					_update_ready_ui()
					if game and data.has("spawns") and data.has("seed"):
						game.start_round_net(data.spawns, int(data.seed))
				"input":
					var pid := int(data.id)
					if not known_pids.has(pid):
						known_pids[pid] = true
						ready_by_pid[pid] = false
						game.add_player_from_net(pid)
						_recalc_host()
					game.set_input_for_pid(pid, data.left, data.right)
				"update":
					if use_input_netmode: continue
					if data.id == my_id: continue
					if not players.has(data.id):
						var p = PLAYER_SCENE.instantiate()
						add_child(p)
						players[data.id] = p
					players[data.id].global_position = Vector2(data.x, data.y)
	elif ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		print("WebSocket closed")



func _unhandled_input(ev):
	if ev is InputEventKey and not ev.echo:
		if ev.pressed and ev.keycode == KEY_R:
			_set_ready(not my_ready)
		if ev.is_action_pressed("ui_accept") and my_id == host_id and game and not game.round_running and known_pids.size() >= MIN_PLAYERS_TO_START:
			var payload := _build_round_start_payload()
			_ws_send(payload)
			game.start_round_net(payload.spawns, payload.seed)

		var left  = Input.is_action_pressed("turn_left")
		var right = Input.is_action_pressed("turn_right")
		if left != last_left or right != last_right:
			last_left = left
			last_right = right
			if my_id != 0 and game:
				game.set_input_for_pid(my_id, left, right)
			_send_input(left, right)


func _send_input(left: bool, right: bool) -> void:
	if ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_ws_send({
		"type": "input",
		"id": my_id,
		"left": left,
		"right": right
	})

func _ws_send(msg: Dictionary) -> void:
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.put_packet(JSON.stringify(msg).to_utf8_buffer())

func _recalc_host() -> void:
	if known_pids.is_empty():
		host_id = 0
	else:
		var ids := known_pids.keys()
		ids.sort()
		host_id = int(ids[0])

func _maybe_start_round() -> void:
	if my_id == host_id and game and not game.round_running and known_pids.size() >= MIN_PLAYERS_TO_START:
		var payload := _build_round_start_payload()
		_ws_send(payload)                                   # an alle
		game.start_round_net(payload.spawns, payload.seed)  # lokal sofort

		print("ROUND_START send", payload)


func _build_round_start_payload() -> Dictionary:
	var spawns := {}
	#for pid in known_pids.keys():
		#spawns[pid] = {
			#"x": randf_range(game.spawn_bounds_x.x, game.spawn_bounds_x.y),
			#"y": randf_range(game.spawn_bounds_y.x, game.spawn_bounds_y.y),
			#"angle": randf_range(0.0, TAU)
		#}
	## globaler Seed (für identische Gap-Randfolgen)
	var sx0: float = game._play_bounds_x.x + game.spawn_extra_margin
	var sx1: float = game._play_bounds_x.y - game.spawn_extra_margin
	var sy0: float = game._play_bounds_y.x + game.spawn_extra_margin
	var sy1: float = game._play_bounds_y.y - game.spawn_extra_margin
	for pid in known_pids.keys():
		spawns[pid] = {
			"x": randf_range(sx0, sx1),
			"y": randf_range(sy0, sy1),
			"angle": randf_range(0.0, TAU)
		}
	var seed := randi()
	var arena := game.get_arena_rect()
	return { "type": "round_start", "seed": seed, "spawns": spawns, "arena": arena}
	
# game_paper.gd
func _host_request_next_round() -> void:
	if my_id == host_id and game and not game.round_running:
		var payload := _build_round_start_payload()
		_ws_send(payload)                                   # an alle Clients
		game.start_round_net(payload.spawns, payload.seed)  # sofort lokal anwenden
		

func _set_ready(v: bool) -> void:
	my_ready = v
	ready_by_pid[my_id] = v
	_update_ready_ui()
	_ws_send({ "type": "ready", "ready": v })

func _wire_ready_button() -> void:
	if not game: 
		return
	var btn: BaseButton = game.get_node_or_null(
		"UI/Control/ReadyCard/Margin/Body/ReadyButton"
	) as BaseButton
	if btn != null:
		btn.toggled.connect(func(on: bool) -> void:
			_set_ready(on)
		)
		
func _update_ready_ui() -> void:
	if not game: return
	# game zeichnet die Anzeige; wir geben Daten rüber
	var ids := known_pids.keys()
	ids.sort()
	if game.has_method("update_ready_ui"):
		game.update_ready_ui(my_id, host_id, ids, ready_by_pid, my_ready)

func _check_all_ready_and_start() -> void:
	if my_id != host_id: return
	if not game or game.round_running: return
	# mindestens alle, die wir kennen, müssen ready sein
	var ids := known_pids.keys()
	if ids.size() == 0: return
	for pid in ids:
		if not ready_by_pid.get(pid, false):
			return  # jemand ist noch nicht ready

	# alle ready -> Runde starten
	var payload := _build_round_start_payload()
	_ws_send(payload)
	game.start_round_net(payload.spawns, payload.seed)
# vereinheitlichte POST-Funktion:
func _post(url: String, body: Dictionary, tag: String) -> void:
	var body_str = JSON.stringify(body)           # string
	var headers = ["Content-Type: application/json"]
	if auth_token != "":
		headers.append("Authorization: Bearer %s" % auth_token)
	# NOTE: je nach Godot-Version ist die Signatur von HTTPRequest.request unterschiedlich.
	# Dieses Aufruf-Format (url, method, headers, body) funktioniert für Godot 4
	var err = http.request(url, headers, HTTPClient.METHOD_POST, body_str)
	if err != OK:
		push_error("HTTP POST konnte nicht gestartet werden: %s" % str(err))
		return
	http.set_meta("last_tag", tag)

# convenience wrappers:
func register_user(username: String, password: String) -> void:
	_post("http://localhost:3000/auth/register", {"username":username,"password":password}, "register")

func login_user(username: String, password: String) -> void:
	_post("http://localhost:3000/auth/login", {"username":username,"password":password}, "login")

func increase_trophy() -> void:
	if auth_token == "":
		push_error("Nicht eingeloggt")
		return
	_post("http://localhost:3000/me/trophies", {"amount":1}, "inc_trophy")

func increase_games() -> void:
	if auth_token == "":
		push_error("Nicht eingeloggt")
		return
	_post("http://localhost:3000/me/games", {"amount":1}, "inc_games")

func _process(_delta):
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		while ws.get_available_packet_count() > 0:
			var msg = ws.get_packet().get_string_from_utf8()
			var data = JSON.parse_string(msg).result
			match data.type:
				"init":
					my_id = data.id
					# lokalen Spieler jetzt erzeugen
					if my_player == null:
						my_player = preload("res://character_body_2d.tscn").instantiate()
						my_player.is_local_player = true
						add_child(my_player)

				"update":
					if not players.has(data.id):
						var p = preload("res://character_body_2d.tscn").instantiate()
						add_child(p)
						players[data.id] = p
					players[data.id].global_position = Vector2(data.x, data.y)
