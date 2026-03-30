class_name GridManager
extends Node

## Manages logical grid, placing, merging, and tracking units on the board.
## Attach this node to the main Level/Game scene.

var _grid_cells: Dictionary = {} # Vector2i -> Node2D (the unit instance)
@export var grid_width: int = 16
@export var grid_height: int = 20

## Called during Game Init
func initialize_grid() -> void:
	for x in range(grid_width):
		for y in range(grid_height):
			_grid_cells[Vector2i(x, y)] = null

## Checks if there is space on the grid, and if so, places a unit.
func summon_unit(grid_pos: Vector2i, unit_scene: PackedScene, unit_data: UnitData) -> void:
	if not is_valid_position(grid_pos) or is_cell_occupied(grid_pos):
		push_warning("Grid cell occupied or invalid at %s" % str(grid_pos))
		return
		
	var unit_instance: Node2D = unit_scene.instantiate()
	
	# We expect units to have a generic setup method, or provide it the data directly
	if unit_instance.has_method("setup_unit"):
		unit_instance.setup_unit(unit_data, grid_pos)

	# Signal Up to let the visual layer (or Game scene) attach the node
	Events.unit_summoned.emit(grid_pos, unit_instance)
	
	_grid_cells[grid_pos] = unit_instance

## Handles attempt to merge two cells
func attempt_merge(pos_a: Vector2i, pos_b: Vector2i, unit_scene: PackedScene) -> void:
	if not is_valid_position(pos_a) or not is_valid_position(pos_b): return
	if pos_a == pos_b: return
	
	var unit_a: Node2D = _grid_cells[pos_a]
	var unit_b: Node2D = _grid_cells[pos_b]
	
	if unit_a == null or unit_b == null: return
	
	# Assume units have an "get_unit_data() -> UnitData" method
	var data_a: UnitData = unit_a.call("get_unit_data")
	var data_b: UnitData = unit_b.call("get_unit_data")
	
	if data_a.can_merge_with(data_b):
		_execute_merge(pos_a, pos_b, unit_a, unit_b, data_a.next_tier_data, unit_scene)
	else:
		# Cannot merge - handle error visually if needed
		push_warning("Cannot merge units at %s and %s" % [str(pos_a), str(pos_b)])

func _execute_merge(pos_a: Vector2i, pos_b: Vector2i, unit_a: Node2D, unit_b: Node2D, next_tier: UnitData, unit_scene: PackedScene) -> void:
	# 1. Clean up old units
	unit_a.queue_free()
	unit_b.queue_free()
	
	# 2. Clear old grid cells
	_grid_cells[pos_a] = null
	_grid_cells[pos_b] = null
	
	# 3. Spawn the new unit at the target position (pos_b for example)
	summon_unit(pos_b, unit_scene, next_tier)
	
	# Fire event if visual effects need triggering independent of normal spawning
	Events.unit_merged.emit(pos_b, next_tier)

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
