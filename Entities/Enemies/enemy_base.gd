class_name EnemyBase
extends CharacterBody2D

## Base class for all enemies
## Designed for mobile optimization: 
## - Disables processing if off-screen (VisibleOnScreenNotifier2D)
## - Built to be pooled, not instantiated and freed repeatedly

@export var data: EnemyData

# Unique Names (%NodeName) used to avoid brittle paths
@onready var sprite: Sprite2D = %Sprite2D
@onready var hit_box: Area2D = %HitBox
@onready var visibility_notifier: VisibleOnScreenNotifier2D = %VisibilityNotifier
@onready var health_bar: ProgressBar = $HealthBar

var current_health: float = 0.0
var path_points: PackedVector2Array = []
var current_path_index: int = 0
var waypoint_reach_distance: float = 22.0

func _ready() -> void:
	add_to_group("enemies")
	if data:
		setup(data)
	
	if visibility_notifier:
		visibility_notifier.screen_exited.connect(_on_screen_exited)
		visibility_notifier.screen_entered.connect(_on_screen_entered)

func setup(enemy_data: EnemyData) -> void:
	data = enemy_data
	current_health = data.max_health
	
	if health_bar:
		health_bar.max_value = data.max_health
		health_bar.value = current_health
	
	if sprite and data.sprite_texture:
		sprite.texture = data.sprite_texture
		
	# TD crowd behavior: gli enemy non devono bloccarsi tra loro.
	collision_layer = 0
	collision_mask = 0

	current_path_index = 0
	set_physics_process(true)

func set_path_points(points: PackedVector2Array) -> void:
	path_points = points
	current_path_index = 0

func _physics_process(delta: float) -> void:
	if data == null or current_health <= 0: return
	_move_along_path(delta)

func _move_along_path(delta: float) -> void:
	if current_path_index >= path_points.size():
		_reach_base()
		return
		
	var target_pos: Vector2 = path_points[current_path_index]
	var to_target: Vector2 = target_pos - global_position
	var reach_dist_sq := waypoint_reach_distance * waypoint_reach_distance

	if to_target.length_squared() <= reach_dist_sq:
		current_path_index += 1
		return

	# Movimento manuale: evita incastri da fisica quando gli enemy sono tanti.
	var step := data.move_speed * delta
	var dist := to_target.length()
	if dist <= step:
		global_position = target_pos
		current_path_index += 1
	else:
		global_position += to_target / dist * step

func take_damage(amount: float) -> void:
	current_health -= amount
	if health_bar:
		health_bar.value = current_health
		
	if current_health <= 0:
		_die()

func _die() -> void:
	current_health = 0
	set_physics_process(false)
	Events.enemy_died.emit(self, data.gold_reward)
	Events.exp_gained.emit(data.exp_reward)

func _reach_base() -> void:
	Events.base_damaged.emit(data.base_damage)
	Events.enemy_died.emit(self, 0)

# --- Mobile Optimization ---
# When enemy leaves the screen view entirely, pause processing (unless they must move offscreen).
# In a TD, enemies often stay on-screen, but this saves CPU if they haven't entered yet or exit bounds.
func _on_screen_exited() -> void:
	# If using ObjectPool, ensure we don't disable a 'dead' or returning enemy indefinitely
	if current_health > 0:
		set_physics_process(false)
		if sprite: sprite.hide()

func _on_screen_entered() -> void:
	if current_health > 0:
		set_physics_process(true)
		if sprite: sprite.show()
