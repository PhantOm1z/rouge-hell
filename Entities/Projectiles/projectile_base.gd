class_name ProjectileBase
extends Area2D

## Projectiles designed for Object Pooling
## Signal Up Call Down for hitting enemies

@export var speed: float = 300.0
@export var impact_radius: float = 0.0 # >0 for splash damage

var _target: Node2D = null
var _damage: float = 0.0
var _active: bool = false
var _pool_origin: StringName = "base_projectile"

# Unique Name
@onready var sprite: Sprite2D = %Sprite2D

func _ready() -> void:
	# Setup for collision layer - assuming enemies are in layer 2, projectiles are masks on 2
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

## Called when acquired from ObjectPool
func setup_projectile(target: Node2D, damage_amount: float) -> void:
	_target = target
	_damage = damage_amount
	_active = true
	
	# Check meta to know where to return to
	if has_meta("pool_origin"):
		_pool_origin = get_meta("pool_origin")

func _physics_process(delta: float) -> void:
	if not _active: return
	
	# Homing logic -> if target dies early, maybe hit ground or despawn
	if _target == null or not is_instance_valid(_target) or _target.get("current_health") <= 0:
		_return_to_pool()
		return
		
	var dir: Vector2 = global_position.direction_to(_target.global_position)
	global_position += dir * speed * delta

func _on_body_entered(body: Node) -> void:
	if not _active: return
	
	# Standard check if it's an enemy
	if body == _target or body is EnemyBase:
		_apply_damage_and_destroy(body)

func _on_area_entered(area: Area2D) -> void:
	if not _active: return
	
	# Alternative check if enemy uses hitboxes (Area2D)
	if area.owner == _target or area.owner is EnemyBase:
		_apply_damage_and_destroy(area.owner)

func _apply_damage_and_destroy(target_node: Node) -> void:
	_active = false
	
	if target_node.has_method("take_damage"):
		target_node.call("take_damage", _damage)
		
	# TODO: Play hit effect / audio via Events
	_return_to_pool()

func _return_to_pool() -> void:
	_active = false
	_target = null
	ObjectPool.release_object(_pool_origin, self)
