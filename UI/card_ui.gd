extends Control
class_name CardUI

## UI Card that can be dragged and dropped onto the Grid

@export var unit_data: UnitData

@onready var texture_rect: TextureRect = $ColorRect/TextureRect
@onready var label: Label = $ColorRect/Label

var is_dragging: bool = false
var start_pos: Vector2

# Riferimento per tornare al mazzo se il drop fallisce (es. casella occupata)
var return_pos: Vector2

func _ready() -> void:
	if unit_data:
		setup(unit_data)

func setup(data: UnitData) -> void:
	unit_data = data
	if texture_rect and data.sprite_texture:
		texture_rect.texture = data.sprite_texture
	if label:
		label.text = data.display_name

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		if event.is_pressed():
			# Inizia a trascinare
			is_dragging = true
			start_pos = global_position
			return_pos = position
			# Sposta la carta sopra alle altre GUI
			top_level = true
			
		elif is_dragging and not event.is_pressed():
			# Rilasciamo il dito dalla carta
			is_dragging = false
			_attempt_drop(get_global_mouse_position())

	if event is InputEventScreenDrag or event is InputEventMouseMotion:
		if is_dragging:
			global_position = get_global_mouse_position() - (size / 2.0)

# Chiamata quando rilasciamo il pulsante per tentare di piazzarla nella griglia di "Main"
func _attempt_drop(drop_global_pos: Vector2) -> void:
	# Lanceremo un evento Global Bus così la Main_Scene (che conosce le celle)
	# controllerà se validato o meno
	Events.call("emit_signal", "card_dropped", self, drop_global_pos)

# Richiamata da `Main` se il piazzamento fallisce
func cancel_drop() -> void:
	top_level = false
	position = return_pos

# Chiamata se il drop ha successo (es. la truppa viene posizionata in griglia)
func confirm_drop() -> void:
	queue_free()
