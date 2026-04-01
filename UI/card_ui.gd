extends Control
class_name CardUI

## UI Card that can be dragged and dropped onto the Grid

@export var unit_data: UnitData

@onready var color_rect: ColorRect = $ColorRect
@onready var outline: ReferenceRect = $Outline
@onready var vbox: VBoxContainer = $VBox
@onready var texture_rect: TextureRect = $VBox/TextureRect
@onready var label: Label = $VBox/Label
@onready var desc_label: Label = $VBox/DescLabel
@onready var preview_sprite: Sprite2D = $PreviewSprite

var is_dragging: bool = false
var start_pos: Vector2
var return_pos: Vector2

func _ready() -> void:
	# Settiamo il centro di rotazione/scala al centro esatto della carta
	pivot_offset = custom_minimum_size / 2.0
	
	outline.border_width = 1.0
	outline.border_color = Color(0.4, 0.4, 0.4, 1.0)
	
	if unit_data:
		setup(unit_data)

func setup(data: UnitData) -> void:
	unit_data = data
	if texture_rect and data.sprite_texture:
		texture_rect.texture = data.sprite_texture
		preview_sprite.texture = data.sprite_texture
	if label:
		label.text = data.display_name
	if desc_label:
		desc_label.text = "Torre Lv.%d\nDanni: %d\nVelocita: %.1f" % [data.tier, int(data.base_damage), data.attack_speed]

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		if event.is_pressed():
			# Clicca per iniziare a trascinare
			is_dragging = true
			start_pos = global_position
			return_pos = position
			top_level = true # Svincola dall'HBoxContainer
			
			_visualize_as_tower()
			Events.call("emit_signal", "card_drag_started", self)
			
		elif is_dragging and not event.is_pressed():
			# Rilascia
			is_dragging = false
			_visualize_as_card()
			Events.call("emit_signal", "card_drag_ended", self)
			_attempt_drop(get_global_mouse_position())

	if event is InputEventScreenDrag or event is InputEventMouseMotion:
		if is_dragging:
			# Il mouse sposta direttamente la preview esattamente sotto al dito
			# (senza offset del size/2 visto che la preview è centrata sullo [0,0] del Control)
			global_position = get_global_mouse_position()
			Events.call("emit_signal", "card_dragged", self, get_global_mouse_position())

func _visualize_as_tower() -> void:
	# Nascondiamo tutta le grafiche della carta rettangolare
	color_rect.hide()
	outline.hide()
	vbox.hide()
	
	# Mostriamo invece la mini-vista della torre trasparente 
	# che rappresenta esattamente come starà nella cella (~45 px)
	preview_sprite.show()
	
	if preview_sprite.texture:
		var tex_width = preview_sprite.texture.get_size().x
		# ~45px è la size delle nostre celle calcolata nel Grid!
		var cell_preview_size = 45.0
		preview_sprite.scale = Vector2.ONE * (cell_preview_size / tex_width) * 0.8
		
	# Resettiamo la scala della Control window che prima si ingrandiva con hover
	scale = Vector2.ONE

func _visualize_as_card() -> void:
	# Ripristiniamo la "Carta" se viene rilasciata nel vuoto o se il drop viene cancellato
	preview_sprite.hide()
	color_rect.show()
	outline.show()
	vbox.show()

# Hover animations per la CARTA (solo quando NON sei in drag)
func _on_mouse_entered() -> void:
	if not is_dragging:
		scale = Vector2(1.05, 1.05)
		outline.border_width = 3.0
		outline.border_color = Color(0.9, 0.75, 0.3, 1)
		position.y -= 20

func _on_mouse_exited() -> void:
	if not is_dragging:
		scale = Vector2.ONE
		outline.border_width = 1.0
		outline.border_color = Color(0.4, 0.4, 0.4, 1.0)
		position.y += 20

# Drop Handling (Signal Up verso main.gd)
func _attempt_drop(drop_global_pos: Vector2) -> void:
	Events.call("emit_signal", "card_dropped", self, drop_global_pos)

func cancel_drop() -> void:
	top_level = false
	position = return_pos

func confirm_drop() -> void:
	queue_free()
