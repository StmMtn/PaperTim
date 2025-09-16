extends Node2D

var ws := WebSocketPeer.new()
var my_id := 0
var players := {}
var http: HTTPRequest
var ws_url := ""

var dev_offline := false

@onready var reconnect_timer := Timer.new()

var game
var known_pids: Dictionary = {}   # { pid: true }
var host_id := 0                  # kleinste PID im Room = Host

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
	http.request_completed.connect(_on_config_response)

	var base_url: String = "http://localhost:8443"
	if Engine.has_singleton("JavaScriptBridge") and OS.has_feature("web"):
		var origin = JavaScriptBridge.eval("window?.location?.origin ?? ''")
		if origin is String and origin != "":
			base_url = origin

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

	ws_url = data["ws_url"]
	_connect_ws()


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
	if dev_offline:
		return

	ws.poll()
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		while ws.get_available_packet_count() > 0:
			var pkt := ws.get_packet().get_string_from_utf8()
			var data: Dictionary = JSON.parse_string(pkt)
			if data == null: continue

			match data.type:
				"update":
					if use_input_netmode: continue
					if data.id == my_id: continue
					if not players.has(data.id):
						var p = PLAYER_SCENE.instantiate()
						add_child(p)
						players[data.id] = p
					players[data.id].global_position = Vector2(data.x, data.y)

				"init":
					# eigene ID vom Server
					my_id = int(data.id)
					if not known_pids.has(my_id):
						game.add_player_from_net(my_id)
						known_pids[my_id] = true
						_recalc_host()
					_maybe_start_round()

				"join":
					# optional: wenn der Server Join-Broadcasts sendet
					var pid := int(data.id)
					if not known_pids.has(pid):
						game.add_player_from_net(pid)
						known_pids[pid] = true
						_recalc_host()
					_maybe_start_round()

				"input":
					var pid := int(data.id)
					if not known_pids.has(pid):
						game.add_player_from_net(pid)
						known_pids[pid] = true
						_recalc_host()
					# eigenes Echo ignorieren nicht nötig, Spielzustand ist lokal
					game.set_input_for_pid(pid, data.left, data.right)

				"remove":
					var rid := int(data.id)
					game.remove_player(rid)
					if known_pids.has(rid):
						known_pids.erase(rid)
						_recalc_host()
					if game.round_running and game.players.size() <= 1:
						game.round_over()
						
						
				"round_start":
					if game and data.has("spawns") and data.has("seed"):
						game.start_round_net(data.spawns, int(data.seed))

				"roster":
					for id in data.ids:
						var pid := int(id)
						if not known_pids.has(pid):
							game.add_player_from_net(pid)
							known_pids[pid] = true
					_recalc_host()
					_maybe_start_round()
	elif ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		print("WebSocket closed")


func _unhandled_input(ev):
	if ev is InputEventKey and not ev.echo:
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
	for pid in known_pids.keys():
		spawns[pid] = {
			"x": randf_range(game.spawn_bounds_x.x, game.spawn_bounds_x.y),
			"y": randf_range(game.spawn_bounds_y.x, game.spawn_bounds_y.y),
			"angle": randf_range(0.0, TAU)
		}
	# globaler Seed (für identische Gap-Randfolgen)
	var seed := randi()
	return { "type": "round_start", "seed": seed, "spawns": spawns }
	
# game_paper.gd
func _host_request_next_round() -> void:
	if my_id == host_id and game and not game.round_running:
		var payload := _build_round_start_payload()
		_ws_send(payload)                                   # an alle Clients
		game.start_round_net(payload.spawns, payload.seed)  # sofort lokal anwenden
		
		
