class_name GridManager
extends Node

var _grid_cells: Dictionary = {} # Vector2i -> Node2D
@export var grid_width: int = 16
@export var grid_height: int = 20

var astar: AStarGrid2D = AStarGrid2D.new()

func initialize_grid() -> void:
	astar.region = Rect2i(0, 0, grid_width, grid_height)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.update()

	for x in range(grid_width):
		for y in range(grid_height):
			_grid_cells[Vector2i(x, y)] = null

func can_place_footprint(start_pos: Vector2i, footprint: Vector2i) -> bool:
	for x in range(footprint.x):
		for y in range(footprint.y):
			var check_pos = start_pos + Vector2i(x, y)
			if not is_valid_position(check_pos) or is_cell_occupied(check_pos):
				return false

	# Simuliamo la chiusura della strada per assicurarci che non blocchi il passaggio.
	for x in range(footprint.x):
		for y in range(footprint.y):
			astar.set_point_solid(start_pos + Vector2i(x, y), true)

	# Deve esistere almeno un percorso da riga alta a riga bassa.
	var is_blocked = true
	for start_x in range(grid_width):
		var start_cell := Vector2i(start_x, 0)
		if astar.is_point_solid(start_cell):
			continue

		for end_x in range(grid_width):
			var end_cell := Vector2i(end_x, grid_height - 1)
			if astar.is_point_solid(end_cell):
				continue

			var path = astar.get_id_path(start_cell, end_cell)
			if path.size() > 0:
				is_blocked = false
				break

		if not is_blocked:
			break

	# Ripristiniamo la griglia dopo il test
	for x in range(footprint.x):
		for y in range(footprint.y):
			astar.set_point_solid(start_pos + Vector2i(x, y), false)

	return not is_blocked

func summon_unit(grid_pos: Vector2i, unit_scene: PackedScene, unit_data: UnitData) -> void:
	if not can_place_footprint(grid_pos, unit_data.footprint):
		return

	var unit_instance: Node2D = unit_scene.instantiate()

	if unit_instance.has_method("setup_unit"):
		unit_instance.setup_unit(unit_data, grid_pos)

	Events.unit_summoned.emit(grid_pos, unit_instance)

	for x in range(unit_data.footprint.x):
		for y in range(unit_data.footprint.y):
			var final_pos = grid_pos + Vector2i(x, y)
			_grid_cells[final_pos] = unit_instance
			astar.set_point_solid(final_pos, true) # Ostacolo fisico IA

	Events.grid_updated.emit()

func attempt_merge(pos_a: Vector2i, pos_b: Vector2i, unit_scene: PackedScene) -> void:
	if not is_valid_position(pos_a) or not is_valid_position(pos_b):
		return
	if pos_a == pos_b:
		return

	var unit_a: Node2D = _grid_cells[pos_a]
	var unit_b: Node2D = _grid_cells[pos_b]
	if unit_a == null or unit_b == null:
		return

	var data_a: UnitData = unit_a.call("get_unit_data")
	var data_b: UnitData = unit_b.call("get_unit_data")

	if data_a.can_merge_with(data_b):
		_execute_merge(pos_a, pos_b, unit_a, unit_b, data_a.next_tier_data, unit_scene)

func _execute_merge(pos_a: Vector2i, pos_b: Vector2i, unit_a: Node2D, unit_b: Node2D, next_tier: UnitData, unit_scene: PackedScene) -> void:
	var fp_a = unit_a.call("get_unit_data").footprint
	var fp_b = unit_b.call("get_unit_data").footprint
	var pos_a_root = unit_a.grid_position
	var pos_b_root = unit_b.grid_position

	unit_a.queue_free()
	unit_b.queue_free()

	# Clear footprints
	for x in range(fp_a.x):
		for y in range(fp_a.y):
			_grid_cells[pos_a_root + Vector2i(x, y)] = null
	for x in range(fp_b.x):
		for y in range(fp_b.y):
			_grid_cells[pos_b_root + Vector2i(x, y)] = null

	summon_unit(pos_b_root, unit_scene, next_tier)
	Events.unit_merged.emit(pos_b_root, next_tier)

func is_valid_position(pos: Vector2i) -> bool:
	return _grid_cells.has(pos)

func is_cell_occupied(pos: Vector2i) -> bool:
	return _grid_cells.get(pos) != null

func get_random_empty_cell() -> Vector2i:
	var empty_cells: Array[Vector2i] = []
	for pos: Vector2i in _grid_cells.keys():
		if _grid_cells[pos] == null:
			empty_cells.append(pos)

	if empty_cells.is_empty():
		return Vector2i(-1, -1)
	return empty_cells.pick_random()
