extends Node2D

@export var max_health: int = 100
var current_health: int = 0

@onready var hp_label: Label = $Label

func _ready() -> void:
	current_health = max_health
	_update_ui()
	Events.base_damaged.connect(_on_base_damaged)

func _on_base_damaged(amount: int) -> void:
	current_health -= amount
	_update_ui()
	
	# Shakeramo visivamente la base (feedback visivo ai danni)
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.2, 1.2), 0.1)
	tween.tween_property(self, "scale", Vector2.ONE, 0.1)
	
	if current_health <= 0:
		Events.game_over.emit()
		print("GAME OVER")
		hp_label.text = "DESTROYED"

func _update_ui() -> void:
	if hp_label:
		hp_label.text = "HP: %d/%d" % [current_health, max_health]
