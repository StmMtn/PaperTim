extends Line2D
@export var max_length_px: float = -1.0   # -1 = unendlich
func _process(_delta: float) -> void:
	if max_length_px <= 0.0: return
	var pts := points
	var n := pts.size()
	if n < 2: return
	var total := 0.0
	var cut_from := 0
	for i in range(n - 2, -1, -1):
		total += pts[i + 1].distance_to(pts[i])
		if total > max_length_px:
			cut_from = i + 1
			break
	if cut_from > 0:
		points = pts.slice(cut_from)
