extends Node2D

@onready var grid_manager: GridManager = $GridManager
@export var unit_scene: PackedScene

var cell_size: float = 0.0
var hovered_cell: Vector2i = Vector2i(-1, -1)
var dragged_card: Control = null

func _ready() -> void:
	cell_size = 720.0 / float(grid_manager.grid_width)
	grid_manager.initialize_grid()
	
	Events.card_dropped.connect(_on_card_dropped)
	Events.card_dragged.connect(_on_card_dragged)
	Events.card_drag_ended.connect(_on_card_drag_ended)
	
	Events.unit_summoned.connect(_on_unit_summoned)

func _draw() -> void:
	var width: int = grid_manager.grid_width
	var height: int = grid_manager.grid_height
	
	for x in range(width + 1):
		draw_line(Vector2(x * cell_size, 0), Vector2(x * cell_size, height * cell_size), Color.DARK_GRAY, 2.0)
	for y in range(height + 1):
		draw_line(Vector2(0, y * cell_size), Vector2(width * cell_size, y * cell_size), Color.DARK_GRAY, 2.0)

	if hovered_cell != Vector2i(-1, -1) and dragged_card != null:
		var fp = dragged_card.unit_data.footprint
		var highlight_color = Color(0.4, 0.9, 1.0, 0.4) # Azzurrino Base (Posizionabile)
		
		if not grid_manager.can_place_footprint(hovered_cell, fp):
			highlight_color = Color(1.0, 0.2, 0.2, 0.4) # ROSSO: non c'è spazio sufficiente (bordi o occupato)
			
		var box_rect = Rect2(hovered_cell.x * cell_size, hovered_cell.y * cell_size, fp.x * cell_size, fp.y * cell_size)
		draw_rect(box_rect, highlight_color, true)

func _get_grid_pos(global_pos: Vector2) -> Vector2i:
	var local_pos = global_pos - global_position
	var grid_x = floori(local_pos.x / cell_size)
	var grid_y = floori(local_pos.y / cell_size)
	return Vector2i(grid_x, grid_y)

func _on_card_dragged(card_ui: Control, drag_pos: Vector2) -> void:
	dragged_card = card_ui
	var target_cell = _get_grid_pos(drag_pos)
	if target_cell != hovered_cell:
		hovered_cell = target_cell
		queue_redraw()

func _on_card_drag_ended(card_ui: Control) -> void:
	dragged_card = null
	hovered_cell = Vector2i(-1, -1)
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
