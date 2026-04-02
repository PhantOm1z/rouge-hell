extends Node2D

@onready var grid_manager: GridManager = $GridManager
@onready var debug_button: Button = $CanvasLayer/TopRightBox/DebugButton
@onready var debug_modal_overlay: Control = $CanvasLayer/DebugModalOverlay
@onready var debug_backdrop: ColorRect = $CanvasLayer/DebugModalOverlay/Backdrop
@onready var debug_add_card_type_select: OptionButton = $CanvasLayer/DebugModalOverlay/ModalPanel/ModalMargin/ModalVBox/DebugAddCardTypeSelect
@onready var debug_add_card_button: Button = $CanvasLayer/DebugModalOverlay/ModalPanel/ModalMargin/ModalVBox/DebugAddCardButton
@onready var debug_layout_select: OptionButton = $CanvasLayer/DebugModalOverlay/ModalPanel/ModalMargin/ModalVBox/DebugLayoutSelect
@onready var debug_close_button: Button = $CanvasLayer/DebugModalOverlay/ModalPanel/ModalMargin/ModalVBox/HeaderRow/CloseDebugButton
@export var unit_scene: PackedScene
@export var repath_interval_seconds: float = 0.2
@export var path_switch_advantage_cells: int = 2
@export var min_placeable_row: int = 3
@export var retreat_lane_offset_cells: float = 1.2

var cell_size: float = 0.0
var hovered_cell: Vector2i = Vector2i(-1, -1)
var dragged_card: Control = null
var repath_accumulator: float = 0.0
var preview_blocked_cells: Array[Vector2i] = []
var has_preview_obstacle: bool = false
var preview_origin_cell: Vector2i = Vector2i(-1, -1)
var preview_footprint: Vector2i = Vector2i.ZERO
var enemy_locked_exit: Dictionary = {} # enemy_instance_id -> bottom exit x
var debug_addable_cards: Array[UnitData] = []
var selected_add_card_data: UnitData = null

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
	debug_button.pressed.connect(_on_debug_button_pressed)
	debug_add_card_button.pressed.connect(_on_add_card_pressed)
	debug_add_card_type_select.item_selected.connect(_on_add_card_type_selected)
	debug_layout_select.item_selected.connect(_on_debug_layout_selected)
	debug_close_button.pressed.connect(_close_debug_modal)
	debug_backdrop.gui_input.connect(_on_debug_backdrop_gui_input)

	selected_time_scale = speeds[speed_index]
	Engine.time_scale = selected_time_scale
	$CanvasLayer/TopRightBox/SpeedButton.text = "Spd: %sx" % selected_time_scale

	_setup_add_card_selector()
	_build_stage_layouts()
	_setup_layout_selector()
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

func _unhandled_input(event: InputEvent) -> void:
	if not debug_modal_overlay.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_close_debug_modal()
		get_viewport().set_input_as_handled()

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

func _on_debug_button_pressed() -> void:
	if debug_modal_overlay.visible:
		_close_debug_modal()
		return
	_open_debug_modal()

func _open_debug_modal() -> void:
	debug_modal_overlay.visible = true

func _close_debug_modal() -> void:
	debug_modal_overlay.visible = false

func _on_debug_backdrop_gui_input(event: InputEvent) -> void:
	var mouse_button := event as InputEventMouseButton
	if mouse_button == null:
		return
	if mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_LEFT:
		_close_debug_modal()

func _on_add_card_pressed() -> void:
	if selected_add_card_data == null and not debug_addable_cards.is_empty():
		selected_add_card_data = debug_addable_cards[0]
	if selected_add_card_data != null:
		_on_card_selected(selected_add_card_data)

func _setup_add_card_selector() -> void:
	debug_addable_cards = [
		preload("res://Resources/Instances/basic_tower.tres") as UnitData,
		preload("res://Resources/Instances/big_tower.tres") as UnitData,
		preload("res://Resources/Instances/mega_tower.tres") as UnitData,
		preload("res://Resources/Instances/wall_tower.tres") as UnitData
	]
	var add_labels: Array[String] = ["Basic", "Big 2x2", "Mega 4x4", "Wall 4x1"]

	debug_add_card_type_select.clear()
	for i in range(debug_addable_cards.size()):
		var option_label: String = add_labels[i] if i < add_labels.size() else debug_addable_cards[i].display_name
		debug_add_card_type_select.add_item(option_label, i)

	if not debug_addable_cards.is_empty():
		debug_add_card_type_select.select(0)
		selected_add_card_data = debug_addable_cards[0]

func _on_add_card_type_selected(index: int) -> void:
	if index < 0 or index >= debug_addable_cards.size():
		return
	selected_add_card_data = debug_addable_cards[index]

func _on_debug_layout_selected(index: int) -> void:
	if index < 0 or index >= stage_layouts.size():
		return
	if index == stage_layout_index:
		return
	_apply_stage_layout(index, true)

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

func _setup_layout_selector() -> void:
	debug_layout_select.clear()
	for i in range(stage_layout_names.size()):
		debug_layout_select.add_item(stage_layout_names[i], i)
	if stage_layout_names.is_empty():
		return
	debug_layout_select.select(clampi(stage_layout_index, 0, stage_layout_names.size() - 1))

func _apply_stage_layout(index: int, clear_units: bool) -> void:
	if index < 0 or index >= stage_layouts.size():
		return

	stage_layout_index = index
	if clear_units:
		_clear_all_enemies_for_layout_change()
		grid_manager.clear_all_units()
	var cells: Array[Vector2i] = stage_layouts[index]
	grid_manager.set_blocked_cells(cells)
	if index < debug_layout_select.item_count:
		debug_layout_select.select(index)
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

		var can_place_here: bool = _is_placement_zone_allowed(hovered_cell, fp) and grid_manager.can_place_footprint(hovered_cell, fp)
		if has_preview_obstacle and hovered_cell == preview_origin_cell and fp == preview_footprint:
			can_place_here = true

		if not can_place_here or _footprint_overlaps_enemy(hovered_cell, fp):
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
		_update_drag_preview_paths(card_ui, hovered_cell)
		queue_redraw()

func _on_card_drag_ended(card_ui: Control) -> void:
	_clear_drag_preview_paths(true)
	dragged_card = null
	hovered_cell = Vector2i(-1, -1)
	Engine.time_scale = selected_time_scale # Ripristina sempre la velocita selezionata
	queue_redraw()

func _on_card_dropped(card_ui: Control, drop_pos: Vector2) -> void:
	_clear_drag_preview_paths(true)
	var target_cell = _get_grid_pos(drop_pos)

	var can_place = _is_placement_zone_allowed(target_cell, card_ui.unit_data.footprint)
	if can_place:
		can_place = grid_manager.can_place_footprint(target_cell, card_ui.unit_data.footprint)
	if can_place:
		can_place = _placement_keeps_all_enemy_paths(target_cell, card_ui.unit_data.footprint)

	if can_place:
		grid_manager.summon_unit(target_cell, unit_scene, card_ui.unit_data)
		card_ui.confirm_drop()
	else:
		card_ui.cancel_drop()

	# Fail-safe: dopo ogni drop torniamo alla velocita scelta dal player.
	Engine.time_scale = selected_time_scale

func _update_drag_preview_paths(card_ui: Control, target_cell: Vector2i) -> void:
	var had_preview := has_preview_obstacle
	if has_preview_obstacle:
		_set_astar_cells_solid(preview_blocked_cells, false)
		preview_blocked_cells.clear()
		has_preview_obstacle = false
		preview_origin_cell = Vector2i(-1, -1)
		preview_footprint = Vector2i.ZERO

	if card_ui == null:
		if had_preview:
			_refresh_paths_for_active_enemies()
		return

	var fp: Vector2i = card_ui.unit_data.footprint
	if not _is_placement_zone_allowed(target_cell, fp):
		if had_preview:
			_refresh_paths_for_active_enemies()
		return
	if not grid_manager.can_place_footprint(target_cell, fp):
		if had_preview:
			_refresh_paths_for_active_enemies()
		return
	if _footprint_overlaps_enemy(target_cell, fp):
		if had_preview:
			_refresh_paths_for_active_enemies()
		return

	preview_blocked_cells = _collect_footprint_cells(target_cell, fp)
	_set_astar_cells_solid(preview_blocked_cells, true)
	has_preview_obstacle = true
	preview_origin_cell = target_cell
	preview_footprint = fp
	_refresh_paths_for_active_enemies()

func _clear_drag_preview_paths(refresh_paths: bool) -> void:
	if not has_preview_obstacle:
		return

	_set_astar_cells_solid(preview_blocked_cells, false)
	preview_blocked_cells.clear()
	has_preview_obstacle = false
	preview_origin_cell = Vector2i(-1, -1)
	preview_footprint = Vector2i.ZERO
	if refresh_paths:
		_refresh_paths_for_active_enemies()

func _collect_footprint_cells(start_pos: Vector2i, footprint: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in range(footprint.x):
		for y in range(footprint.y):
			var cell = start_pos + Vector2i(x, y)
			if cell.x < 0 or cell.y < 0:
				continue
			if cell.x >= grid_manager.grid_width or cell.y >= grid_manager.grid_height:
				continue
			cells.append(cell)
	return cells

func _set_astar_cells_solid(cells: Array[Vector2i], is_solid: bool) -> void:
	for cell in cells:
		grid_manager.astar.set_point_solid(cell, is_solid)

func _is_placement_zone_allowed(start_pos: Vector2i, footprint: Vector2i) -> bool:
	if start_pos.y < min_placeable_row:
		return false
	if start_pos.x < 0 or start_pos.y < 0:
		return false
	if start_pos.x + footprint.x > grid_manager.grid_width:
		return false
	if start_pos.y + footprint.y > grid_manager.grid_height:
		return false
	return true

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

		var path_ids = _find_best_path_ids(start_grid, enemy.global_position)
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
		var tower := unit as UnitBase
		var tex_size = sprite.texture.get_size()
		if tower != null and tower.data != null and tower.data.ability == UnitData.AbilityType.WALL:
			var sx: float = (cell_size * float(fp.x) / maxf(tex_size.x, 1.0)) * 0.8
			var sy: float = (cell_size * float(fp.y) / maxf(tex_size.y, 1.0)) * 0.8
			sprite.scale = Vector2(sx, sy)
		else:
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

	var path_ids = _find_stable_path_ids(enemy, start_grid, enemy.global_position)
	var global_path: PackedVector2Array = []
	var force_path_from_start: bool = false
	if path_ids.is_empty():
		global_path = _build_retreat_world_path(enemy.global_position, enemy.get_instance_id())
		force_path_from_start = not global_path.is_empty()
	else:
		for id in path_ids:
			var world_pos = global_position + Vector2(id.x * cell_size + cell_size / 2.0, id.y * cell_size + cell_size / 2.0)
			global_path.append(world_pos)

	var enemy_base: EnemyBase = enemy as EnemyBase
	if enemy_base != null:
		enemy_base.set_path_points(global_path, force_path_from_start)

func _refresh_paths_for_active_enemies() -> void:
	var active_enemy_ids: Dictionary = {}
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as EnemyBase
		if enemy == null or enemy.current_health <= 0:
			continue
		active_enemy_ids[enemy.get_instance_id()] = true
		_update_path_for_enemy(enemy)

	for enemy_id in enemy_locked_exit.keys():
		if not active_enemy_ids.has(enemy_id):
			enemy_locked_exit.erase(enemy_id)

func _find_stable_path_ids(enemy: Node2D, start_grid: Vector2i, enemy_world_pos: Vector2) -> Array[Vector2i]:
	var best_path := _find_best_path_ids(start_grid, enemy_world_pos)
	if best_path.is_empty():
		return best_path

	var enemy_id := enemy.get_instance_id()
	var best_goal_x := _extract_bottom_goal_x(best_path)
	var has_locked_goal := enemy_locked_exit.has(enemy_id)
	if not has_locked_goal:
		enemy_locked_exit[enemy_id] = best_goal_x
		return best_path

	var locked_goal_x := int(enemy_locked_exit[enemy_id])
	if locked_goal_x == best_goal_x:
		return best_path

	var locked_path := _find_path_to_bottom_exit(start_grid, locked_goal_x)
	if locked_path.is_empty():
		enemy_locked_exit[enemy_id] = best_goal_x
		return best_path

	if locked_path.size() <= best_path.size() + path_switch_advantage_cells:
		return locked_path

	enemy_locked_exit[enemy_id] = best_goal_x
	return best_path

func _extract_bottom_goal_x(path: Array[Vector2i]) -> int:
	if path.is_empty():
		return -1
	return path[path.size() - 1].x

func _find_path_to_bottom_exit(start_grid: Vector2i, end_x: int) -> Array[Vector2i]:
	if end_x < 0 or end_x >= grid_manager.grid_width:
		return []

	var end_cell := Vector2i(end_x, grid_manager.grid_height - 1)
	if grid_manager.astar.is_point_solid(end_cell):
		return []

	return grid_manager.astar.get_id_path(start_grid, end_cell)

func _get_retreat_lane_y() -> float:
	return global_position.y + (cell_size * 0.5) - (cell_size * retreat_lane_offset_cells)

func _build_retreat_world_path(enemy_world_pos: Vector2, enemy_id: int) -> PackedVector2Array:
	var best_world_path: PackedVector2Array = PackedVector2Array()
	var best_score: float = INF
	var best_goal_x := -1

	var locked_goal_x := -1
	if enemy_locked_exit.has(enemy_id):
		locked_goal_x = int(enemy_locked_exit[enemy_id])

	var locked_world_path: PackedVector2Array = PackedVector2Array()
	var locked_score: float = INF

	for entry_x in range(grid_manager.grid_width):
		var entry_cell := Vector2i(entry_x, 0)
		if grid_manager.astar.is_point_solid(entry_cell):
			continue

		var entry_path := _find_best_bottom_path(entry_cell)
		if entry_path.is_empty():
			continue

		var candidate_world := _build_world_path_via_entry(enemy_world_pos, entry_x, entry_path)
		if candidate_world.is_empty():
			continue

		var score: float = _score_world_path(enemy_world_pos, candidate_world)
		var goal_x: int = entry_path[entry_path.size() - 1].x

		if goal_x == locked_goal_x and score < locked_score:
			locked_score = score
			locked_world_path = candidate_world

		if score < best_score:
			best_score = score
			best_world_path = candidate_world
			best_goal_x = goal_x

	if best_world_path.is_empty():
		return best_world_path

	if not locked_world_path.is_empty():
		var switch_margin := float(path_switch_advantage_cells) * cell_size
		if locked_score <= best_score + switch_margin:
			return locked_world_path

	enemy_locked_exit[enemy_id] = best_goal_x
	return best_world_path

func _build_world_path_via_entry(enemy_world_pos: Vector2, entry_x: int, entry_path: Array[Vector2i]) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	var retreat_lane_y: float = _get_retreat_lane_y()
	var min_world_x: float = global_position.x + (cell_size * 0.5)
	var max_world_x: float = global_position.x + (cell_size * (float(grid_manager.grid_width) - 0.5))
	var retreat_up_x: float = clampf(enemy_world_pos.x, min_world_x, max_world_x)
	var retreat_up_world: Vector2 = Vector2(retreat_up_x, retreat_lane_y)
	var retreat_world := Vector2(global_position.x + (float(entry_x) * cell_size) + (cell_size * 0.5), _get_retreat_lane_y())
	var entry_world := _grid_to_world(Vector2i(entry_x, 0))
	if result.is_empty() or result[result.size() - 1].distance_squared_to(retreat_up_world) > 1.0:
		result.append(retreat_up_world)
	if result.is_empty() or result[result.size() - 1].distance_squared_to(retreat_world) > 1.0:
		result.append(retreat_world)
	if result.is_empty() or result[result.size() - 1].distance_squared_to(entry_world) > 1.0:
		result.append(entry_world)

	for cell in entry_path:
		var world_point: Vector2 = _grid_to_world(cell)
		if result.is_empty() or result[result.size() - 1].distance_squared_to(world_point) > 1.0:
			result.append(world_point)

	return result

func _score_world_path(origin: Vector2, path: PackedVector2Array) -> float:
	if path.is_empty():
		return INF

	var score := origin.distance_to(path[0])
	for i in range(path.size() - 1):
		score += path[i].distance_to(path[i + 1])

	return score

func _find_best_path_ids(start_grid: Vector2i, enemy_world_pos: Vector2) -> Array[Vector2i]:
	var best_path := _find_best_bottom_path(start_grid)
	var best_score := INF
	if not best_path.is_empty():
		best_score = float(best_path.size())

	var top_band_limit := global_position.y + cell_size * 3.0
	if enemy_world_pos.y > top_band_limit:
		return best_path

	for entry_x in range(grid_manager.grid_width):
		var entry_cell := Vector2i(entry_x, 0)
		if grid_manager.astar.is_point_solid(entry_cell):
			continue

		var candidate_path := _find_best_bottom_path(entry_cell)
		if candidate_path.is_empty():
			continue

		var entry_world := _grid_to_world(entry_cell)
		var lateral_cost := absf(entry_world.x - enemy_world_pos.x) / maxf(cell_size, 1.0)
		var score := float(candidate_path.size()) + lateral_cost * 0.85

		if score < best_score:
			best_score = score
			best_path = candidate_path

	return best_path

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

func _grid_to_world(cell: Vector2i) -> Vector2:
	return global_position + Vector2(cell.x * cell_size + cell_size / 2.0, cell.y * cell_size + cell_size / 2.0)

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
