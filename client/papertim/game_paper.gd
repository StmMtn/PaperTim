extends Node2D

var ws := WebSocketPeer.new()

func _ready():
	ws.connect_to_url("ws://localhost:8080")
	print("Connecting...")

func _process(delta):
	ws.poll()
	var state = ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		ws.put_packet("Hello from client".to_utf8_buffer())
	elif state == WebSocketPeer.STATE_CLOSED:
		print("WebSocket closed")
