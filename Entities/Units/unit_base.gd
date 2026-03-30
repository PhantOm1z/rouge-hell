class_name UnitBase
extends Node2D

## Base class for allied Units (Towers)
## Handles attack logic, range detection, and displaying data from UnitData

@export var data: UnitData

# Unique Names for mobile optimization & decoupled scene structure
@onready var sprite: Sprite2D = %Sprite2D
@onready var range_area: Area2D = %RangeArea
@onready var collision_shape: CollisionShape2D = %RangeShape
@onready var attack_timer: Timer = %AttackTimer

var grid_position: Vector2i = Vector2i.ZERO
var current_target: EnemyBase = null
var current_level: int = 1

func _ready() -> void:
	if data != null:
		setup_unit(data, grid_position)

## Injected from GridManager or Level upon summon/merge
func setup_unit(unit_data: UnitData, pos: Vector2i) -> void:
	data = unit_data
	grid_position = pos
	
	# Initialize visuals
	if sprite and data.sprite_texture:
		sprite.texture = data.sprite_texture
	
	# Initialize range shape
	if collision_shape and collision_shape.shape is CircleShape2D:
		(collision_shape.shape as CircleShape2D).radius = data.attack_range
		
	# Setup Attack Timer
	if attack_timer:
		attack_timer.wait_time = 1.0 / data.attack_speed
		if not attack_timer.timeout.is_connected(_on_attack_timer_timeout):
			attack_timer.timeout.connect(_on_attack_timer_timeout)

func get_unit_data() -> UnitData:
	return data

func _physics_process(delta: float) -> void:
	if data == null: return
	
	# If no target or target left range / died
	if not is_instance_valid(current_target) or current_target.current_health <= 0:
		_find_new_target()
	else:
		# Check if we should attack
		if attack_timer.is_stopped():
			attack_timer.start()

func _find_new_target() -> void:
	current_target = null
	var enemies_in_range: Array[Area2D] = range_area.get_overlapping_areas()
	
	# Mobile TD optimization: Just pick the first closest one, or oldest one.
	for area: Area2D in enemies_in_range:
		# L'Area2D si chiama HitBox ed è figlia diretta di EnemyBase
		var enemy: EnemyBase = area.get_parent() as EnemyBase
		if enemy != null and enemy.current_health > 0:
			current_target = enemy
			if attack_timer.is_stopped(): attack_timer.start()
			break
			
	if current_target == null:
		attack_timer.stop()

func _on_attack_timer_timeout() -> void:
	if current_target != null and is_instance_valid(current_target):
		# Create projectile via Object Pooling
		# In a real setup, we'd pass 'data.projectile_scene' to a pool
		var proj: Node2D = ObjectPool.acquire_object("base_projectile")
		if proj and proj.has_method("setup_projectile"):
			# Signal Up -> Let Level add it correctly so it doesn't move with the unit
			Events.call_deferred("add_child", proj) # Safe fallback or use Event Bus correctly
			proj.global_position = global_position
			proj.setup_projectile(current_target, data.base_damage)
	else:
		# Force re-scan next frame
		current_target = null
