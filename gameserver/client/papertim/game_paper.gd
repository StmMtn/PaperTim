extends Node2D

var ws := WebSocketPeer.new()
var my_id := 0
var players := {}   # andere Spieler
var my_player = null

func _ready():
	ws.connect_to_url("wss://localhost:8443")
	print("Connecting...")

	# Eigenen Player instanzieren
	my_player = preload("res://character_body_2d.tscn").instantiate()
	my_player.is_local_player = true    # <<< Nur mein Spieler reagiert auf Eingabe
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
						# Ignorieren, weil wir unseren eigenen Player lokal bewegen
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
