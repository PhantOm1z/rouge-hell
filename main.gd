extends Node2D

@onready var grid_manager: GridManager = $GridManager
@export var unit_scene: PackedScene

var cell_size: float = 0.0
var hovered_cell: Vector2i = Vector2i(-1, -1)
var dragged_card: Control = null
var previous_time_scale: float = 1.0

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
	
	# Dopo 3 secondi dall'avvio, la griglia chiama la prima Wave letale
	await get_tree().create_timer(3.0).timeout
	$WaveManager.start_next_wave()

var speed_index: int = 1
var speeds: Array[float] = [0.5, 1.0, 2.0, 3.0]

func _on_speed_pressed() -> void:
	speed_index = (speed_index + 1) % speeds.size()
	var new_speed = speeds[speed_index]
	Engine.time_scale = new_speed
	$CanvasLayer/TopRightBox/SpeedButton.text = "Spd: %sx" % new_speed

func _on_pause_pressed() -> void:
	get_tree().paused = not get_tree().paused
	$CanvasLayer/TopRightBox/PauseButton.text = "Resume" if get_tree().paused else "Pause"

func _on_restart_pressed() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	for child in ObjectPool.get_children():
		child.queue_free()
	get_tree().reload_current_scene()

func _on_wave_started(wave_idx: int) -> void:
	var total = $WaveManager.max_waves
	$CanvasLayer/TopLeftBox/WaveLabel.text = "WAVE: %d/%d" % [wave_idx, total]

func _draw() -> void:
	var width: int = grid_manager.grid_width
	var height: int = grid_manager.grid_height
	
	for x in range(width + 1):
		draw_line(Vector2(x * cell_size, 0), Vector2(x * cell_size, height * cell_size), Color.DARK_GRAY, 2.0)
	for y in range(height + 1):
		draw_line(Vector2(0, y * cell_size), Vector2(width * cell_size, y * cell_size), Color.DARK_GRAY, 2.0)

	if hovered_cell != Vector2i(-1, -1) and dragged_card != null:
		var fp = dragged_card.unit_data.footprint
		var highlight_color = Color(0.4, 0.9, 1.0, 0.4) # Posizionabile
		
		if not grid_manager.can_place_footprint(hovered_cell, fp):
			highlight_color = Color(1.0, 0.2, 0.2, 0.4) # Sbagliato
			
		var box_rect = Rect2(hovered_cell.x * cell_size, hovered_cell.y * cell_size, fp.x * cell_size, fp.y * cell_size)
		draw_rect(box_rect, highlight_color, true)
		
		# Disegna forma specifica in base all'abilità
		var center_pos = Vector2(hovered_cell.x * cell_size + (fp.x * cell_size)/2.0, hovered_cell.y * cell_size + (fp.y * cell_size)/2.0)
		var ability = dragged_card.unit_data.ability
		var range_val = dragged_card.unit_data.attack_range
		
		# In unit_data.gd: NORMAL=0, TWIN_SIDES=1, FLAMETHROWER=2, QUAKE=3
		if ability == 1 or ability == 2:
			# Entrambi sparano in linee orizzontali strette (Destra e Sinistra!)
			var beam_color = Color(1.0, 1.0, 0.3, 0.2) # Giallastro per i proiettili base (1x1)
			if ability == 2:
				beam_color = Color(1.0, 0.3, 0.0, 0.3) # Arancione inteso per il Flamethrower (2x2)
				
			# Costruiamo il rettangolo di tiro centrato sulla torre, largo 2*Range e alto "footprint_cells"
			var beam_rect = Rect2(center_pos.x - range_val, hovered_cell.y * cell_size, range_val * 2, fp.y * cell_size)
			draw_rect(beam_rect, beam_color, true)
		else:
			# Attacchi a tutto tondo: Quake o Torri Classiche
			var circle_color = Color(1.0, 1.0, 1.0, 0.15)
			if ability == 3:
				circle_color = Color(0.8, 0.2, 0.8, 0.2) # Violetto minaccioso per AoE Boss-Smasher
			draw_circle(center_pos, range_val, circle_color)

func _get_grid_pos(global_pos: Vector2) -> Vector2i:
	var local_pos = global_pos - global_position
	var grid_x = floori(local_pos.x / cell_size)
	var grid_y = floori(local_pos.y / cell_size)
	return Vector2i(grid_x, grid_y)

func _on_card_drag_started(card_ui: Control) -> void:
	previous_time_scale = Engine.time_scale
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
	Engine.time_scale = previous_time_scale # Ripristiniamo la velocità di prima
	queue_redraw()

func _on_card_dropped(card_ui: Control, drop_pos: Vector2) -> void:
	var target_cell = _get_grid_pos(drop_pos)
	
	if grid_manager.can_place_footprint(target_cell, card_ui.unit_data.footprint):
		grid_manager.summon_unit(target_cell, unit_scene, card_ui.unit_data)
		card_ui.confirm_drop()
	else:
		card_ui.cancel_drop()

func _on_unit_summoned(grid_pos: Vector2i, unit: Node2D) -> void:
	var fp = unit.data.footprint
	add_child(unit)
	unit.position = Vector2(grid_pos.x * cell_size + (fp.x * cell_size)/2.0, grid_pos.y * cell_size + (fp.y * cell_size)/2.0)
	
	var sprite = unit.get_node("%Sprite2D")
	if sprite and sprite.texture:
		var tex_size = sprite.texture.get_size()
		# Lo scaliamo rispetto al lato minore del rettangolo o semplicemente il minimo dei due scale
		var max_side = min(fp.x, fp.y)
		sprite.scale = Vector2(1,1) * (cell_size * max_side / tex_size.x) * 0.8

func _on_enemy_spawned(enemy: Node2D) -> void:
	if enemy.get_parent() == null:
		add_child(enemy)

# --- RPG & Progression Logic ---
var current_exp: int = 0
var exp_to_next: int = 10
var player_level: int = 1

func _on_exp_gained(amount: int) -> void:
	current_exp += amount
	
	if current_exp >= exp_to_next:
		current_exp -= exp_to_next
		player_level += 1
		exp_to_next = int(exp_to_next * 1.5) # Scala la difficoltà (es. 10 -> 15 -> 22 -> 33)
		
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
	# Quando viene messa o tolta una torre, ricalcola il percorso di tutti!
	for enemy in get_tree().get_nodes_in_group("enemies"):
		_update_path_for_enemy(enemy)

func _update_path_for_enemy(enemy: Node2D) -> void:
	if not is_instance_valid(enemy): return
	
	# Da dove parte (limitato nei bordi per vitare crash AStar)
	var start_grid = _get_grid_pos(enemy.global_position)
	start_grid.x = clampi(start_grid.x, 0, grid_manager.grid_width - 1)
	start_grid.y = clampi(start_grid.y, 0, grid_manager.grid_height - 1)
	
	# Verso dove va (Fine della plancia in mezzo)
	var end_grid = Vector2i(grid_manager.grid_width / 2, grid_manager.grid_height - 1)
	
	var path_ids = grid_manager.astar.get_id_path(start_grid, end_grid)
	var global_path: PackedVector2Array = []
	for id in path_ids:
		var world_pos = global_position + Vector2(id.x * cell_size + cell_size/2.0, id.y * cell_size + cell_size/2.0)
		global_path.append(world_pos)
		
	if global_path.size() > 0:
		if enemy.has_method("set_path_points"):
			enemy.set_path_points(global_path)
