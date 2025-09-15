extends Node2D

var ws := WebSocketPeer.new()
var my_id := 0
var players := {}
var my_player = null

var http: HTTPRequest
var ws_url := ""

var dev_offline := true  # zum schnellen Testen auf true

var ws_status := -1
@onready var reconnect_timer := Timer.new()

var game
var known_pids := {}  

# NEU: Umschalter – wenn true, steuern wir Player per Input-Nachrichten statt Positions-"update"
var use_input_netmode := true
# NEU: Wenn du lokal als "Host" testest und der Server Inputs nicht verteilt, 	kannst du hier true setzen und eingehende Inputs direkt anwenden. 
var is_host := false

const PLAYER_SCENE := preload("res://kurve/player.tscn")
# alt:
# const PLAYER_SCENE := preload("res://character_body_2d.tscn")

func _ready():
	reconnect_timer.one_shot = true
	add_child(reconnect_timer)
	reconnect_timer.timeout.connect(_connect_ws)
	if dev_offline:
		_connect_ws()   # <-- sofort los
		return
	http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_config_response)

	var base_url: String = "http://localhost:8443"
	 # Nur im Web/HTML5 versuchen, die Origin zu lesen
	if Engine.has_singleton("JavaScriptBridge") and OS.has_feature("web"):
		var origin = JavaScriptBridge.eval("window?.location?.origin ?? ''")
		if origin is String and origin != "":
			base_url = origin

	var err = http.request(base_url + "/config")
	if err != OK:
		push_error("Config-Request konnte nicht gestartet werden: %s" % str(err))
		_connect_with_fallback()

func _on_config_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_error("Config konnte nicht geladen werden (result=%s, code=%s)" % [str(result), str(response_code)])
		_connect_with_fallback()
		return

	var text := body.get_string_from_utf8()
	var data = JSON.parse_string(text)
	if data == null or not data.has("ws_url"):
		push_error("Config-JSON ungültig: %s" % text)
		_connect_with_fallback()
		return

	ws_url = data["ws_url"]
	_connect_ws()

func _connect_with_fallback():
	ws_url = "ws://localhost:8443"
	_connect_ws()

func _connect_ws():
	print("DEV-OFFLINE: loading game.tscn…")
	if dev_offline:
		var game_packed = load("res://kurve/game.tscn")
		game = game_packed.instantiate()
		game.network_driven = true
		add_child(game)
		my_id = 1
		print("DEV-OFFLINE: add player ", my_id)
		game.add_player_from_net(my_id)
		if not game.round_running:
			game.start_round()
			print("DEV-OFFLINE: start_round()")
		return

	ws = WebSocketPeer.new()
	var err = ws.connect_to_url(ws_url)
	if err != OK:
		push_error("WS-Verbindung fehlgeschlagen: %s" % str(err))


	#my_player = PLAYER_SCENE.instantiate()
	#if "is_local_player" in my_player:
		#my_player.is_local_player = true
	#add_child(my_player)
	#my_player.player_num = 1  # temporär; später aus Lobby/Server
	#my_player.start()

func _process(delta):
	if dev_offline:
		return  # kein WS-Poll nötig
	ws.poll()
	var state = ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		while ws.get_available_packet_count() > 0:
			var data = JSON.parse_string(ws.get_packet().get_string_from_utf8())
			if data == null: continue
			match data.type:
				"update":
					if use_input_netmode:
						continue
					if data.id == my_id:
						continue
					if not players.has(data.id):
						var p = PLAYER_SCENE.instantiate()
						add_child(p)
						players[data.id] = p
					players[data.id].global_position = Vector2(data.x, data.y)

				"init":
					my_id = int(data.id)
					if not known_pids.has(my_id):
						game.add_player_from_net(my_id)
						known_pids[my_id] = true
					if not game.round_running:
						game.start_round()

					#var pid = int(data.id)
					#if not known_pids.has(pid):
						#game.add_player_from_net(pid)
						#known_pids[pid] = true
					#game.set_input_for_pid(pid, data.left, data.right)
					#if data.id == my_id:
						#continue
					#if not players.has(data.id):
						#var p = PLAYER_SCENE.instantiate()
						#add_child(p)
						#players[data.id] = p
						#p.player_num = int(data.id) % 4 + 1  # simple Zuordnung
						#p.start()
					#players[data.id].set_input(data.left, data.right)
					
				"input":
					var pid := int(data.id)
					if not known_pids.has(pid):
						game.add_player_from_net(pid)
						known_pids[pid] = true
					# Optional: eigenes Echo ignorieren
					if pid != my_id:
						game.set_input_for_pid(pid, data.left, data.right)


				"remove":
					game.remove_player(int(data.id))
					known_pids.erase(int(data.id))

					#if players.has(data.id):
						#players[data.id].queue_free()
						#players.erase(data.id)
	elif state == WebSocketPeer.STATE_CLOSED:
		print("WebSocket closed")

func _unhandled_input(ev):
	if ev is InputEventKey and not ev.echo:
		var left  = Input.is_action_pressed("turn_left")
		var right = Input.is_action_pressed("turn_right")
		if my_id != 0:
			game.set_input_for_pid(my_id, left, right)
		_send_input(left, right)
		#if my_player and "set_input" in my_player:
			#my_player.set_input(left, right)
		#_send_input(left, right)
	if ev is InputEventKey and ev.pressed and not ev.echo:
		print("pressed:", ev.keycode, " L=", Input.is_action_pressed("turn_left"), " R=", Input.is_action_pressed("turn_right"))
	var left  = Input.is_action_pressed("turn_left")
	var right = Input.is_action_pressed("turn_right")
	if my_id != 0 and game:
		game.set_input_for_pid(my_id, left, right)

func _send_input(left: bool, right: bool) -> void:
	if ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var msg = {
		"type": "input",
		"id": my_id,
		"left": left,
		"right": right
	}
	ws.put_packet(JSON.stringify(msg).to_utf8_buffer())

func send_position(pos: Vector2):
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var msg = {"x": pos.x, "y": pos.y}
		ws.put_packet(JSON.stringify(msg).to_utf8_buffer())
