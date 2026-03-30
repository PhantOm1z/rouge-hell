extends ColorRect
class_name DraftUI

var possible_cards: Array[Resource] = [
	preload("res://Resources/Instances/basic_tower.tres"),
	preload("res://Resources/Instances/big_tower.tres"),
	preload("res://Resources/Instances/mega_tower.tres")
]

func _ready() -> void:
	hide()

func open_draft() -> void:
	show()
	get_tree().paused = true
	
	for i in range(3):
		var btn = $HBoxContainer.get_child(i) as Button
		# Pesca casualmente dal pool (per ora mescoliamo quelle 3, in futuro avrai più file)
		var data: UnitData = possible_cards.pick_random()
		btn.text = data.display_name + "\n(Danno: " + str(data.base_damage) + ")"
		
		# Pulisce vecchi segnali per non sommarli
		if btn.pressed.get_connections().size() > 0:
			var conns = btn.pressed.get_connections()
			for c in conns:
				btn.pressed.disconnect(c.callable)
				
		btn.pressed.connect(_on_card_picked.bind(data))

func _on_card_picked(data: UnitData) -> void:
	Events.select_draft_card.emit(data)
	hide()
	get_tree().paused = false
