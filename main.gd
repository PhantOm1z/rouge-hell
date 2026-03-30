extends Node2D

@onready var grid_manager: GridManager = $GridManager
@export var unit_scene: PackedScene

var cell_size: float = 0.0

func _ready() -> void:
	# Calcoliamo la grandezza della cella dinamicamente in base allo schermo (720px)
	cell_size = 720.0 / float(grid_manager.grid_width)
	
	grid_manager.initialize_grid()
	
	# Ascoltiamo la magia della UI: trascinamento carte!
	Events.card_dropped.connect(_on_card_dropped)
	Events.unit_summoned.connect(_on_unit_summoned)
	Events.unit_merged.connect(_on_unit_merged)

func _draw() -> void:
	# Griglia logica in stile scacchiera visibile
	var width: int = grid_manager.grid_width
	var height: int = grid_manager.grid_height
	
	for x in range(width + 1):
		draw_line(Vector2(x * cell_size, 0), Vector2(x * cell_size, height * cell_size), Color.DARK_GRAY, 2.0)
	for y in range(height + 1):
		draw_line(Vector2(0, y * cell_size), Vector2(width * cell_size, y * cell_size), Color.DARK_GRAY, 2.0)

# Converte la posizione globale del dito/mouse in coordinate della griglia interna
func _get_grid_pos(global_pos: Vector2) -> Vector2i:
	var local_pos = global_pos - global_position
	var grid_x = floori(local_pos.x / cell_size)
	var grid_y = floori(local_pos.y / cell_size)
	return Vector2i(grid_x, grid_y)

func _on_card_dropped(card_ui: Control, drop_pos: Vector2) -> void:
	var target_cell = _get_grid_pos(drop_pos)
	
	# Controlliamo la validità della casella in base alle regole pure del GridManager
	if grid_manager.is_valid_position(target_cell):
		
		# Controlliamo il MERGE (unione): se la cella è già occupata, proviamo a unire le torri
		if grid_manager.is_cell_occupied(target_cell):
			# Il merge implementato in futuro
			pass
			
		# Mettiamo la prima pedina
		if not grid_manager.is_cell_occupied(target_cell):
			grid_manager.summon_unit(target_cell, unit_scene, card_ui.unit_data)
			card_ui.confirm_drop() # Consuma la carta dalla mano!
			return
			
	# Se finiamo qui, non potevamo piazzarla
	card_ui.cancel_drop()

func _on_unit_summoned(grid_pos: Vector2i, unit: Node2D) -> void:
	add_child(unit)
	unit.position = Vector2(grid_pos.x * cell_size + cell_size/2.0, grid_pos.y * cell_size + cell_size/2.0)
	
	# Scaliamo automaticamente la grafica della torre per farla stare precisamente nella cella! (80% della cella presa)
	var sprite = unit.get_node("%Sprite2D")
	if sprite and sprite.texture:
		var tex_size = sprite.texture.get_size()
		sprite.scale = Vector2(1,1) * (cell_size / tex_size.x) * 0.8

func _on_unit_merged(grid_pos: Vector2i, new_unit_data: Resource) -> void:
	pass
