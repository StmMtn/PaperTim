extends Node2D

var ws := WebSocketPeer.new()
var my_id := 0
var players := {}
var my_player = null

var http: HTTPRequest
var ws_url := ""
var auth_token := ""
var me := {}  # user info

func _ready():
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

	http.set_meta("last_tag", "config")
	var err = http.request(base_url + "/config")
	if err != OK:
		push_error("Config-Request konnte nicht gestartet werden: %s" % str(err))
		_connect_with_fallback()

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
	var err = ws.connect_to_url(ws_url)
	if err != OK:
		push_error("WS-Verbindung fehlgeschlagen: %s" % str(err))
		return
	print("Connecting to %s" % ws_url)

	my_player = preload("res://character_body_2d.tscn").instantiate()
	my_player.is_local_player = true
	add_child(my_player)

func send_position(pos: Vector2):
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var msg = {"x": pos.x, "y": pos.y}
		ws.put_packet(JSON.stringify(msg).to_utf8_buffer())

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
