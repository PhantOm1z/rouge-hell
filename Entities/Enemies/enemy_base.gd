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
var path_lookahead_steps: int = 3
var lateral_blend_weight: float = 0.35
var has_valid_path: bool = false
var has_entered_screen_once: bool = false
var is_eliminated: bool = false

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
	is_eliminated = false
	
	if health_bar:
		health_bar.max_value = data.max_health
		health_bar.value = current_health
	
	if sprite and data.sprite_texture:
		sprite.texture = data.sprite_texture
		
	# TD crowd behavior: gli enemy non devono bloccarsi tra loro.
	collision_layer = 0
	collision_mask = 0

	path_points = PackedVector2Array()
	current_path_index = 0
	has_valid_path = false
	has_entered_screen_once = false
	if sprite:
		sprite.show()
	if health_bar:
		health_bar.show()
	set_physics_process(true)

func set_path_points(points: PackedVector2Array) -> void:
	if _is_same_path(points):
		return

	path_points = points
	if path_points.is_empty():
		current_path_index = 0
		has_valid_path = false
		return

	has_valid_path = true
	current_path_index = _find_closest_waypoint_index(global_position)
	_consume_reached_waypoints()

func _is_same_path(new_points: PackedVector2Array) -> bool:
	if not has_valid_path:
		return false
	if path_points.size() != new_points.size():
		return false

	for i in range(path_points.size()):
		if path_points[i].distance_squared_to(new_points[i]) > 1.0:
			return false

	return true

func _physics_process(delta: float) -> void:
	if data == null or current_health <= 0 or is_eliminated: return
	_move_along_path(delta)

func _move_along_path(delta: float) -> void:
	if not has_valid_path or path_points.is_empty():
		return

	if current_path_index >= path_points.size():
		_reach_base()
		return

	_consume_reached_waypoints()

	if current_path_index >= path_points.size():
		_reach_base()
		return

	var target_pos: Vector2 = path_points[current_path_index]
	var to_target: Vector2 = target_pos - global_position

	var step := data.move_speed * delta
	var dist := to_target.length()
	if dist <= 0.001:
		current_path_index += 1
		return

	if dist <= step:
		global_position = target_pos
		current_path_index += 1
	else:
		var move_dir := to_target / dist
		var lookahead_idx := mini(current_path_index + path_lookahead_steps, path_points.size() - 1)
		if lookahead_idx > current_path_index:
			var lookahead_vec := path_points[lookahead_idx] - global_position
			var lookahead_len := lookahead_vec.length()
			if lookahead_len > 0.001:
				var lookahead_dir := lookahead_vec / lookahead_len
				move_dir = (move_dir * (1.0 - lateral_blend_weight) + lookahead_dir * lateral_blend_weight).normalized()

		global_position += move_dir * step

func _find_closest_waypoint_index(pos: Vector2) -> int:
	var closest_index := 0
	var closest_dist_sq := INF

	for i in range(path_points.size()):
		var d := pos.distance_squared_to(path_points[i])
		if d < closest_dist_sq:
			closest_dist_sq = d
			closest_index = i

	return closest_index

func _consume_reached_waypoints() -> void:
	var reach_dist_sq := waypoint_reach_distance * waypoint_reach_distance
	while current_path_index < path_points.size():
		if global_position.distance_squared_to(path_points[current_path_index]) <= reach_dist_sq:
			current_path_index += 1
		else:
			break

func take_damage(amount: float) -> void:
	if is_eliminated:
		return

	current_health -= amount
	if health_bar:
		health_bar.value = current_health
		
	if current_health <= 0:
		_die()

func _die() -> void:
	if is_eliminated:
		return
	is_eliminated = true
	current_health = 0
	has_valid_path = false
	set_physics_process(false)
	Events.enemy_died.emit(self, data.gold_reward)
	Events.exp_gained.emit(data.exp_reward)

func _reach_base() -> void:
	if is_eliminated:
		return
	is_eliminated = true
	current_health = 0
	has_valid_path = false
	set_physics_process(false)
	Events.base_damaged.emit(data.base_damage)
	Events.enemy_died.emit(self, 0)

# --- Mobile Optimization ---
# When enemy leaves the screen view entirely, pause processing (unless they must move offscreen).
# In a TD, enemies often stay on-screen, but this saves CPU if they haven't entered yet or exit bounds.
func _on_screen_exited() -> void:
	# If using ObjectPool, ensure we don't disable a 'dead' or returning enemy indefinitely
	if current_health > 0 and has_entered_screen_once and not is_eliminated:
		set_physics_process(false)
		if sprite:
			sprite.hide()
		if health_bar:
			health_bar.hide()

func _on_screen_entered() -> void:
	if current_health > 0 and not is_eliminated:
		has_entered_screen_once = true
		set_physics_process(true)
		if sprite:
			sprite.show()
		if health_bar:
			health_bar.show()
