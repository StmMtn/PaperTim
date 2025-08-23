extends Node2D

var ws := WebSocketPeer.new()
var my_id := 0
var players := {}
var my_player = null

var http: HTTPRequest
var ws_url := ""

func _ready():
	http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_config_response)

	var base_url := ""
	# Im Web absolute Origin abfragen
	if Engine.has_singleton("JavaScriptBridge"):
		base_url = JavaScriptBridge.eval("window.location.origin")
	else:
		# Fallback, wenn nicht im Web
		base_url = "http://localhost:8443"

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
	var err = ws.connect_to_url(ws_url)
	if err != OK:
		push_error("WS-Verbindung fehlgeschlagen: %s" % str(err))
		return
	print("Connecting to %s" % ws_url)

	my_player = preload("res://character_body_2d.tscn").instantiate()
	my_player.is_local_player = true
	add_child(my_player)

func _process(delta):
	ws.poll()
	var state = ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		while ws.get_available_packet_count() > 0:
			var raw_msg = ws.get_packet().get_string_from_utf8()
			var data = JSON.parse_string(raw_msg)
			if data == null:
				continue
			match data.type:
				"init":
					my_id = data.id
					print("My ID: %s" % my_id)
				"update":
					if data.id == my_id:
						continue
					if not players.has(data.id):
						var new_player = preload("res://character_body_2d.tscn").instantiate()
						add_child(new_player)
						players[data.id] = new_player
					players[data.id].global_position = Vector2(data.x, data.y)
				"remove":
					if players.has(data.id):
						players[data.id].queue_free()
						players.erase(data.id)
	elif state == WebSocketPeer.STATE_CLOSED:
		print("WebSocket closed")

func send_position(pos: Vector2):
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var msg = {"x": pos.x, "y": pos.y}
		ws.put_packet(JSON.stringify(msg).to_utf8_buffer())
