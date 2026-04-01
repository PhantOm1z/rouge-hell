extends Area2D
class_name ProjectileBase

@export var speed: float = 600.0
var damage: float = 0.0
var direction: Vector2 = Vector2.ZERO

func _ready() -> void:
	area_entered.connect(_on_area_entered)

func setup(dmg: float, dir: Vector2, custom_speed: float = -1.0) -> void:
	damage = dmg
	direction = dir.normalized()
	if custom_speed > 0:
		speed = custom_speed
	rotation = direction.angle()

func _physics_process(delta: float) -> void:
	position += direction * speed * delta

func _on_area_entered(area: Area2D) -> void:
	if not area.name == "HitBox": return
	
	var enemy = area.get_parent()
	if enemy and enemy.has_method("take_damage"):
		enemy.take_damage(damage)
		ObjectPool.release_object("base_projectile", self)

# Pulisce visibilità estrema
func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	ObjectPool.release_object("base_projectile", self)
