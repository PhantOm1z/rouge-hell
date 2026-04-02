class_name EnemyBase
extends CharacterBody2D

## Base class for all enemies
## Designed for mobile optimization:
## - Lean movement step
## - Pool-friendly reset
## - Lightweight hitbox setup

@export var data: EnemyData
@export var show_health_bar: bool = false

const HITBOX_LAYER: int = 1 << 2
const WAYPOINT_REACH_DISTANCE: float = 22.0

# Unique Names (%NodeName) used to avoid brittle paths
@onready var sprite: Sprite2D = %Sprite2D
@onready var hit_box: Area2D = %HitBox
@onready var health_bar: ProgressBar = get_node_or_null("HealthBar") as ProgressBar

var current_health: float = 0.0
var path_points: PackedVector2Array = []
var current_path_index: int = 0
var waypoint_reach_distance_sq: float = WAYPOINT_REACH_DISTANCE * WAYPOINT_REACH_DISTANCE
var has_valid_path: bool = false
var is_eliminated: bool = false

func _ready() -> void:
	add_to_group("enemies")
	if data:
		setup(data)

func setup(enemy_data: EnemyData) -> void:
	data = enemy_data
	current_health = data.max_health
	is_eliminated = false

	if sprite and data.sprite_texture:
		sprite.texture = data.sprite_texture

	# TD crowd behavior: enemies do not collide with each other.
	collision_layer = 0
	collision_mask = 0
	if hit_box:
		hit_box.monitoring = false
		hit_box.monitorable = true
		hit_box.collision_layer = HITBOX_LAYER
		hit_box.collision_mask = 0

	path_points = PackedVector2Array()
	current_path_index = 0
	has_valid_path = false
	if sprite:
		sprite.show()
	if health_bar:
		if show_health_bar:
			health_bar.max_value = data.max_health
			health_bar.value = current_health
			health_bar.show()
		else:
			health_bar.hide()
	set_physics_process(true)

func set_path_points(points: PackedVector2Array, force_from_start: bool = false) -> void:
	if _is_same_path(points):
		return

	path_points = points
	if path_points.is_empty():
		current_path_index = 0
		has_valid_path = false
		return

	has_valid_path = true
	if force_from_start:
		current_path_index = 0
	else:
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

	var step: float = data.move_speed * delta
	var dist_sq: float = to_target.length_squared()
	if dist_sq <= 0.001:
		current_path_index += 1
		return

	var step_sq: float = step * step
	if dist_sq <= step_sq:
		global_position = target_pos
		current_path_index += 1
		return

	global_position += to_target * (step / sqrt(dist_sq))

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
	while current_path_index < path_points.size():
		if global_position.distance_squared_to(path_points[current_path_index]) <= waypoint_reach_distance_sq:
			current_path_index += 1
		else:
			break

func take_damage(amount: float) -> void:
	if is_eliminated:
		return

	current_health -= amount
	if health_bar and show_health_bar:
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
	var gold_reward: int = data.gold_reward if data != null else 0
	var exp_reward: int = data.exp_reward if data != null else 0
	Events.enemy_died.emit(self, gold_reward)
	Events.exp_gained.emit(exp_reward)

func _reach_base() -> void:
	if is_eliminated:
		return
	is_eliminated = true
	current_health = 0
	has_valid_path = false
	set_physics_process(false)
	var base_damage: int = data.base_damage if data != null else 1
	Events.base_damaged.emit(base_damage)
	Events.enemy_died.emit(self, 0)
