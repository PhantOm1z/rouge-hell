extends Node2D

@onready var grid_manager: GridManager = $GridManager
@export var unit_scene: PackedScene
@export var repath_interval_seconds: float = 0.35

var cell_size: float = 0.0
var hovered_cell: Vector2i = Vector2i(-1, -1)
var dragged_card: Control = null
var repath_accumulator: float = 0.0

func _ready() -> void:
	# Pool Setup automatico per caricare pallottole e nemici veloci per Android
	var proj_scene = preload("res://Entities/Projectiles/projectile_base.tscn")
	var enemy_scene = preload("res://Entities/Enemies/enemy_base.tscn")
	ObjectPool.register_pool("base_projectile", proj_scene, 50)
	ObjectPool.register_pool("common_enemy", enemy_scene, 50)

	cell_size = 720.0 / float(grid_manager.grid_width)
	grid_manager.initialize_grid()

	Events.card_dropped.connect(_on_card_dropped)
	Events.card_drag_started.connect(_on_card_drag_started)
	Events.card_dragged.connect(_on_card_dragged)
	Events.card_drag_ended.connect(_on_card_drag_ended)

	Events.unit_summoned.connect(_on_unit_summoned)
	Events.enemy_spawned.connect(_on_enemy_spawned)
	Events.wave_started.connect(_on_wave_started)
	Events.grid_updated.connect(_on_grid_updated)

	Events.exp_gained.connect(_on_exp_gained)
	Events.select_draft_card.connect(_on_card_selected)

	$CanvasLayer/TopRightBox/SpeedButton.pressed.connect(_on_speed_pressed)
	$CanvasLayer/TopRightBox/PauseButton.pressed.connect(_on_pause_pressed)
	$CanvasLayer/TopRightBox/RestartButton.pressed.connect(_on_restart_pressed)
	$CanvasLayer/TopRightBox/AddCardButton.pressed.connect(_on_add_card_pressed)
	$CanvasLayer/TopRightBox/LayoutButton.pressed.connect(_on_layout_button_pressed)

	selected_time_scale = speeds[speed_index]
	Engine.time_scale = selected_time_scale
	$CanvasLayer/TopRightBox/SpeedButton.text = "Spd: %sx" % selected_time_scale

	_build_stage_layouts()
	_apply_stage_layout(0, false)

	# Dopo 3 secondi dall'avvio, la griglia chiama la prima Wave letale
	await get_tree().create_timer(3.0).timeout
	$WaveManager.start_next_wave()

func _process(delta: float) -> void:
	if repath_interval_seconds <= 0.0:
		return

	repath_accumulator += delta
	if repath_accumulator < repath_interval_seconds:
		return

	repath_accumulator = 0.0
	_refresh_paths_for_active_enemies()

var speed_index: int = 1
var speeds: Array[float] = [0.5, 1.0, 2.0, 3.0]
var selected_time_scale: float = 1.0
var stage_layout_index: int = 0
var stage_layout_names: Array[String] = []
var stage_layouts: Array = []

func _on_speed_pressed() -> void:
	speed_index = (speed_index + 1) % speeds.size()
	selected_time_scale = speeds[speed_index]
	if dragged_card == null:
		Engine.time_scale = selected_time_scale
	$CanvasLayer/TopRightBox/SpeedButton.text = "Spd: %sx" % selected_time_scale

func _on_pause_pressed() -> void:
	get_tree().paused = not get_tree().paused
	$CanvasLayer/TopRightBox/PauseButton.text = "Resume" if get_tree().paused else "Pause"

func _on_restart_pressed() -> void:
	speed_index = 1
	selected_time_scale = speeds[speed_index]
	Engine.time_scale = selected_time_scale
	$CanvasLayer/TopRightBox/SpeedButton.text = "Spd: %sx" % selected_time_scale
	get_tree().paused = false
	for child in ObjectPool.get_children():
		child.queue_free()
	get_tree().reload_current_scene()

func _on_add_card_pressed() -> void:
	# Debug: aggiunge una carta Big Tower ogni volta che premi il bottone.
	_on_card_selected(preload("res://Resources/Instances/big_tower.tres"))

func _on_layout_button_pressed() -> void:
	if stage_layouts.is_empty():
		return
	stage_layout_index = (stage_layout_index + 1) % stage_layouts.size()
	_apply_stage_layout(stage_layout_index, true)

func _build_stage_layouts() -> void:
	stage_layout_names = ["Layout 1", "Layout 2", "Layout 3"]
	stage_layouts.clear()

	var layout1: Array[Vector2i] = []
	layout1.append_array(_cells_rect(1, 5, 5, 1))
	layout1.append_array(_cells_rect(10, 5, 5, 1))
	layout1.append_array(_cells_rect(4, 10, 8, 1))
	layout1.append_array(_cells_rect(2, 15, 5, 1))
	layout1.append_array(_cells_rect(10, 15, 4, 1))
	stage_layouts.append(layout1)

	var layout2: Array[Vector2i] = []
	layout2.append_array(_cells_rect(2, 3, 12, 1))
	layout2.append_array(_cells_rect(2, 8, 12, 1))
	layout2.append_array(_cells_rect(2, 13, 12, 1))
	layout2.append_array(_cells_rect(7, 4, 1, 3))
	layout2.append_array(_cells_rect(9, 9, 1, 3))
	stage_layouts.append(layout2)

	var layout3: Array[Vector2i] = []
	layout3.append_array(_cells_rect(0, 6, 6, 1))
	layout3.append_array(_cells_rect(10, 6, 6, 1))
	layout3.append_array(_cells_rect(5, 9, 1, 6))
	layout3.append_array(_cells_rect(10, 9, 1, 6))
	layout3.append_array(_cells_rect(3, 16, 10, 1))
	stage_layouts.append(layout3)

func _apply_stage_layout(index: int, clear_units: bool) -> void:
	if index < 0 or index >= stage_layouts.size():
		return

	stage_layout_index = index
	if clear_units:
		_clear_all_enemies_for_layout_change()
		grid_manager.clear_all_units()
	var cells: Array[Vector2i] = stage_layouts[index]
	grid_manager.set_blocked_cells(cells)
	$CanvasLayer/TopRightBox/LayoutButton.text = stage_layout_names[index]
	queue_redraw()

func _cells_rect(x: int, y: int, w: int, h: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			cells.append(Vector2i(xx, yy))
	return cells

func _clear_all_enemies_for_layout_change() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as EnemyBase
		if enemy == null:
			continue
		if enemy.current_health <= 0:
			continue
		enemy.current_health = 0
		enemy.set_physics_process(false)
		Events.enemy_died.emit(enemy, 0)

func _on_wave_started(wave_idx: int) -> void:
	var total = $WaveManager.max_waves
	$CanvasLayer/TopLeftBox/WaveLabel.text = "WAVE: %d/%d" % [wave_idx, total]

func _draw() -> void:
	var width: int = grid_manager.grid_width
	var height: int = grid_manager.grid_height

	for cell in grid_manager.get_blocked_cells():
		var rect = Rect2(cell.x * cell_size, cell.y * cell_size, cell_size, cell_size)
		draw_rect(rect, Color(0.42, 0.31, 0.18, 0.9), true)

	for x in range(width + 1):
		draw_line(Vector2(x * cell_size, 0), Vector2(x * cell_size, height * cell_size), Color.DARK_GRAY, 2.0)
	for y in range(height + 1):
		draw_line(Vector2(0, y * cell_size), Vector2(width * cell_size, y * cell_size), Color.DARK_GRAY, 2.0)

	if hovered_cell != Vector2i(-1, -1) and dragged_card != null:
		var fp = dragged_card.unit_data.footprint
		var highlight_color = Color(0.4, 0.9, 1.0, 0.4) # Posizionabile

		if not grid_manager.can_place_footprint(hovered_cell, fp) or _footprint_overlaps_enemy(hovered_cell, fp):
			highlight_color = Color(1.0, 0.2, 0.2, 0.4) # Sbagliato

		var box_rect = Rect2(hovered_cell.x * cell_size, hovered_cell.y * cell_size, fp.x * cell_size, fp.y * cell_size)
		draw_rect(box_rect, highlight_color, true)

		# Disegna forma specifica in base all'abilita
		var center_pos = Vector2(hovered_cell.x * cell_size + (fp.x * cell_size) / 2.0, hovered_cell.y * cell_size + (fp.y * cell_size) / 2.0)
		var ability = dragged_card.unit_data.ability
		var range_val = dragged_card.unit_data.attack_range

		# In unit_data.gd: NORMAL=0, TWIN_SIDES=1, FLAMETHROWER=2, QUAKE=3
		if ability == 1 or ability == 2:
			# Entrambi sparano in linee orizzontali strette (destra e sinistra)
			var beam_color = Color(1.0, 1.0, 0.3, 0.2)
			if ability == 2:
				beam_color = Color(1.0, 0.3, 0.0, 0.3)

			# Rettangolo di tiro centrato sulla torre, largo 2*range e alto footprint
			var beam_rect = Rect2(center_pos.x - range_val, hovered_cell.y * cell_size, range_val * 2, fp.y * cell_size)
			draw_rect(beam_rect, beam_color, true)
		else:
			# Attacchi a tutto tondo: Quake o torri classiche
			var circle_color = Color(1.0, 1.0, 1.0, 0.15)
			if ability == 3:
				circle_color = Color(0.8, 0.2, 0.8, 0.2)
			draw_circle(center_pos, range_val, circle_color)

func _get_grid_pos(global_pos: Vector2) -> Vector2i:
	var local_pos = global_pos - global_position
	var grid_x = floori(local_pos.x / cell_size)
	var grid_y = floori(local_pos.y / cell_size)
	return Vector2i(grid_x, grid_y)

func _on_card_drag_started(card_ui: Control) -> void:
	Engine.time_scale = 0.1 # Rallentamento tattico immediato

func _on_card_dragged(card_ui: Control, drag_pos: Vector2) -> void:
	dragged_card = card_ui
	var target_cell = _get_grid_pos(drag_pos)
	if target_cell != hovered_cell:
		hovered_cell = target_cell
		queue_redraw()

func _on_card_drag_ended(card_ui: Control) -> void:
	dragged_card = null
	hovered_cell = Vector2i(-1, -1)
	Engine.time_scale = selected_time_scale # Ripristina sempre la velocita selezionata
	queue_redraw()

func _on_card_dropped(card_ui: Control, drop_pos: Vector2) -> void:
	var target_cell = _get_grid_pos(drop_pos)

	var can_place = grid_manager.can_place_footprint(target_cell, card_ui.unit_data.footprint)
	if can_place:
		can_place = _placement_keeps_all_enemy_paths(target_cell, card_ui.unit_data.footprint)

	if can_place:
		grid_manager.summon_unit(target_cell, unit_scene, card_ui.unit_data)
		card_ui.confirm_drop()
	else:
		card_ui.cancel_drop()

	# Fail-safe: dopo ogni drop torniamo alla velocita scelta dal player.
	Engine.time_scale = selected_time_scale

func _placement_keeps_all_enemy_paths(start_pos: Vector2i, footprint: Vector2i) -> bool:
	# Non permettere placement sopra nemici vivi: evita soft-lock e stalli.
	if _footprint_overlaps_enemy(start_pos, footprint):
		return false

	# Simula il blocco footprint e verifica che tutti i nemici attivi abbiano ancora un path.
	var simulated_cells: Array[Vector2i] = []
	for x in range(footprint.x):
		for y in range(footprint.y):
			var cell = start_pos + Vector2i(x, y)
			if grid_manager.astar.is_point_solid(cell):
				# Should not happen if can_place_footprint e' gia' true, ma teniamo guardia.
				for rollback_cell in simulated_cells:
					grid_manager.astar.set_point_solid(rollback_cell, false)
				return false
			grid_manager.astar.set_point_solid(cell, true)
			simulated_cells.append(cell)

	var all_ok := true
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as EnemyBase
		if enemy == null or enemy.current_health <= 0:
			continue

		var start_grid = _get_grid_pos(enemy.global_position)
		start_grid.x = clampi(start_grid.x, 0, grid_manager.grid_width - 1)
		start_grid.y = clampi(start_grid.y, 0, grid_manager.grid_height - 1)
		start_grid = _find_nearest_walkable_cell(start_grid)

		var path_ids = _find_best_bottom_path(start_grid)
		if path_ids.is_empty():
			all_ok = false
			break

	for rollback_cell in simulated_cells:
		grid_manager.astar.set_point_solid(rollback_cell, false)

	return all_ok

func _footprint_overlaps_enemy(start_pos: Vector2i, footprint: Vector2i) -> bool:
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as EnemyBase
		if enemy == null or enemy.current_health <= 0:
			continue

		var enemy_cell = _get_grid_pos(enemy.global_position)
		enemy_cell.x = clampi(enemy_cell.x, 0, grid_manager.grid_width - 1)
		enemy_cell.y = clampi(enemy_cell.y, 0, grid_manager.grid_height - 1)

		if enemy_cell.x >= start_pos.x and enemy_cell.x < start_pos.x + footprint.x:
			if enemy_cell.y >= start_pos.y and enemy_cell.y < start_pos.y + footprint.y:
				return true

	return false

func _on_unit_summoned(grid_pos: Vector2i, unit: Node2D) -> void:
	var fp = unit.data.footprint
	add_child(unit)
	unit.position = Vector2(grid_pos.x * cell_size + (fp.x * cell_size) / 2.0, grid_pos.y * cell_size + (fp.y * cell_size) / 2.0)

	var sprite = unit.get_node("%Sprite2D")
	if sprite and sprite.texture:
		var tex_size = sprite.texture.get_size()
		# Lo scaliamo rispetto al lato minore del rettangolo o semplicemente il minimo dei due scale
		var max_side = min(fp.x, fp.y)
		sprite.scale = Vector2(1, 1) * (cell_size * max_side / tex_size.x) * 0.8

func _on_enemy_spawned(enemy: Node2D) -> void:
	if enemy.get_parent() == null:
		add_child(enemy)
	_update_path_for_enemy(enemy)

# --- RPG & Progression Logic ---
var current_exp: int = 0
var exp_to_next: int = 10
var player_level: int = 1

func _on_exp_gained(amount: int) -> void:
	current_exp += amount

	if current_exp >= exp_to_next:
		current_exp -= exp_to_next
		player_level += 1
		exp_to_next = int(exp_to_next * 1.5) # Scala la difficolta (es. 10 -> 15 -> 22 -> 33)

		# Apriamo la tendina Draft 1 di 3
		$CanvasLayer/DraftUI.open_draft()

	_update_rpg_ui()

func _update_rpg_ui() -> void:
	var lbl = $CanvasLayer/LevelBox/LevelLabel
	var bar = $CanvasLayer/LevelBox/ExpBar
	if lbl and bar:
		lbl.text = "Livello %d" % player_level
		bar.max_value = exp_to_next
		bar.value = current_exp

func _on_card_selected(data: UnitData) -> void:
	# Istanzia un nuovo nodo Carta pescata e posizionalo nel HandContainer
	var new_card = preload("res://UI/card_ui.tscn").instantiate()
	new_card.unit_data = data
	$CanvasLayer/HandContainer.add_child(new_card)

# --- Pathfinding AI (AStarGrid2D) ---
func _on_grid_updated() -> void:
	# Quando viene messa o tolta una torre, ricalcola subito il percorso di tutti.
	_refresh_paths_for_active_enemies()
	queue_redraw()

func _update_path_for_enemy(enemy: Node2D) -> void:
	if not is_instance_valid(enemy):
		return
	if enemy is EnemyBase and enemy.current_health <= 0:
		return

	# Da dove parte (limitato nei bordi per evitare crash AStar)
	var start_grid = _get_grid_pos(enemy.global_position)
	start_grid.x = clampi(start_grid.x, 0, grid_manager.grid_width - 1)
	start_grid.y = clampi(start_grid.y, 0, grid_manager.grid_height - 1)
	start_grid = _find_nearest_walkable_cell(start_grid)

	var path_ids = _find_best_bottom_path(start_grid)
	var global_path: PackedVector2Array = []
	for id in path_ids:
		var world_pos = global_position + Vector2(id.x * cell_size + cell_size / 2.0, id.y * cell_size + cell_size / 2.0)
		global_path.append(world_pos)

	if enemy.has_method("set_path_points"):
		enemy.set_path_points(global_path)

func _refresh_paths_for_active_enemies() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as EnemyBase
		if enemy == null or enemy.current_health <= 0:
			continue
		_update_path_for_enemy(enemy)

func _find_best_bottom_path(start_grid: Vector2i) -> Array[Vector2i]:
	var best_path: Array[Vector2i] = []

	for end_x in range(grid_manager.grid_width):
		var end_cell := Vector2i(end_x, grid_manager.grid_height - 1)
		if grid_manager.astar.is_point_solid(end_cell):
			continue

		var candidate_path = grid_manager.astar.get_id_path(start_grid, end_cell)
		if candidate_path.is_empty():
			continue

		if best_path.is_empty() or candidate_path.size() < best_path.size():
			best_path = candidate_path

	return best_path

func _find_nearest_walkable_cell(origin: Vector2i) -> Vector2i:
	if not grid_manager.astar.is_point_solid(origin):
		return origin

	var max_radius = maxi(grid_manager.grid_width, grid_manager.grid_height)
	for radius in range(1, max_radius + 1):
		for y in range(origin.y - radius, origin.y + radius + 1):
			for x in range(origin.x - radius, origin.x + radius + 1):
				var candidate := Vector2i(x, y)
				if candidate.x < 0 or candidate.y < 0:
					continue
				if candidate.x >= grid_manager.grid_width or candidate.y >= grid_manager.grid_height:
					continue
				if not grid_manager.astar.is_point_solid(candidate):
					return candidate

	return origin
