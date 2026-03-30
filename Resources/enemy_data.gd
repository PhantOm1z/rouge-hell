class_name EnemyData
extends Resource

## Data container for enemies
## Use .tres files to configure different enemy types (e.g. Slime, Goblin)

@export var enemy_id: StringName = "basic_slime"
@export var display_name: String = "Slime"
@export var max_health: float = 50.0
@export var move_speed: float = 40.0
@export var base_damage: int = 1
@export var gold_reward: int = 1
@export var exp_reward: int = 1
@export var budget_cost: float = 10.0

@export_group("Visuals")
@export var sprite_texture: Texture2D
