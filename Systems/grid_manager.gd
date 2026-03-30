class_name GridManager
extends Node

var _grid_cells: Dictionary = {} # Vector2i -> Node2D
@export var grid_width: int = 16
@export var grid_height: int = 20

func initialize_grid() -> void:
	for x in range(grid_width):
		for y in range(grid_height):
			_grid_cells[Vector2i(x, y)] = null

func can_place_footprint(start_pos: Vector2i, footprint: Vector2i) -> bool:
	for x in range(footprint.x):
		for y in range(footprint.y):
			var check_pos = start_pos + Vector2i(x, y)
			if not is_valid_position(check_pos) or is_cell_occupied(check_pos):
				return false
	return true

func summon_unit(grid_pos: Vector2i, unit_scene: PackedScene, unit_data: UnitData) -> void:
	if not can_place_footprint(grid_pos, unit_data.footprint):
		push_warning("Grid footprint occupied or invalid at %s" % str(grid_pos))
		return
		
	var unit_instance: Node2D = unit_scene.instantiate()
	
	if unit_instance.has_method("setup_unit"):
		unit_instance.setup_unit(unit_data, grid_pos)

	Events.unit_summoned.emit(grid_pos, unit_instance)
	
	for x in range(unit_data.footprint.x):
		for y in range(unit_data.footprint.y):
			_grid_cells[grid_pos + Vector2i(x, y)] = unit_instance

func attempt_merge(pos_a: Vector2i, pos_b: Vector2i, unit_scene: PackedScene) -> void:
	if not is_valid_position(pos_a) or not is_valid_position(pos_b): return
	if pos_a == pos_b: return
	
	var unit_a: Node2D = _grid_cells[pos_a]
	var unit_b: Node2D = _grid_cells[pos_b]
	if unit_a == null or unit_b == null: return
	
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
			_grid_cells[pos_a_root + Vector2i(x,y)] = null
	for x in range(fp_b.x):
		for y in range(fp_b.y):
			_grid_cells[pos_b_root + Vector2i(x,y)] = null
			
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
