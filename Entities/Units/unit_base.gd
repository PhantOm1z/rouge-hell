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
@onready var flame_beam: ColorRect = %FlameBeam

var grid_position: Vector2i = Vector2i.ZERO
var current_target: EnemyBase = null
var current_level: int = 1

# -- Variabili per Flamethrower --
var is_flaming: bool = false
var flame_dir: float = 1.0 # 1 per destra, -1 per sinistra
var flame_duration: float = 0.0

func _ready() -> void:
	if data != null:
		setup_unit(data, grid_position)

func setup_unit(unit_data: UnitData, pos: Vector2i) -> void:
	data = unit_data
	grid_position = pos
	
	if sprite and data.sprite_texture:
		sprite.texture = data.sprite_texture
	
	if collision_shape and collision_shape.shape is CircleShape2D:
		(collision_shape.shape as CircleShape2D).radius = data.attack_range
	
	if flame_beam: # Il lanciafiamme arriva quanto il raggio di tiro
		flame_beam.size.x = data.attack_range
		flame_beam.hide()
		
	if attack_timer:
		attack_timer.wait_time = 1.0 / data.attack_speed
		if not attack_timer.timeout.is_connected(_on_attack_timer_timeout):
			attack_timer.timeout.connect(_on_attack_timer_timeout)

func get_unit_data() -> UnitData:
	return data

func _physics_process(delta: float) -> void:
	if data == null: return
	
	# Logica danni lanciafiamme (Continuo per X secondi su un solo lato)
	if is_flaming:
		flame_duration -= delta
		if flame_duration <= 0:
			_stop_flamethrower()
		else:
			# Danno nel tempo (DoT) a tutti i presenti dal lato giusto
			var enemies = range_area.get_overlapping_areas()
			for area: Area2D in enemies:
				if area.name == "HitBox":
					var e = area.get_parent() as EnemyBase
					if e and e.current_health > 0:
						var dist_x = e.global_position.x - global_position.x
						# Controlliamo l'orientamento
						if (flame_dir > 0 and dist_x > 0) or (flame_dir < 0 and dist_x < 0):
							# Danno per secondo bilanciato
							e.take_damage(data.base_damage * delta * 4) 
		return # Mentre lanciafiamme blocca altre logiche
	
	if not is_instance_valid(current_target) or current_target.current_health <= 0:
		_find_new_target()
	else:
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
	_shoot()

func _shoot() -> void:
	if current_target == null or current_target.current_health <= 0:
		_find_new_target()
		if current_target == null:
			attack_timer.stop()
			return
			
	match data.ability:
		UnitData.AbilityType.NORMAL:
			var dir = global_position.direction_to(current_target.global_position)
			_fire_proj(dir)
		UnitData.AbilityType.TWIN_SIDES:
			_fire_proj(Vector2.LEFT)
			_fire_proj(Vector2.RIGHT)
		UnitData.AbilityType.FLAMETHROWER:
			_start_flamethrower()
		UnitData.AbilityType.QUAKE:
			# Area of Effect ISTANTANEO su tutto quello che è nel range
			for area: Area2D in range_area.get_overlapping_areas():
				if area.name == "HitBox":
					var e = area.get_parent()
					if e and e.has_method("take_damage"):
						e.take_damage(data.base_damage)

func _start_flamethrower() -> void:
	is_flaming = true
	flame_duration = 2.0 # Dura 2 secondi per ricarica
	attack_timer.stop()  # Chiude il cronometro finché sgancia fiamme
	
	# Sceglie la direzione in un istante a seconda del Target salvato
	if current_target.global_position.x > global_position.x:
		flame_dir = 1.0
		flame_beam.scale.x = 1
	else:
		flame_dir = -1.0
		flame_beam.scale.x = -1
		
	flame_beam.show()

func _stop_flamethrower() -> void:
	is_flaming = false
	flame_beam.hide()
	# Rimette in ciclo il cooldown standard finiti i 2 Secondi
	attack_timer.start()

func _fire_proj(dir: Vector2, custom_speed: float = -1.0) -> void:
	var proj = ObjectPool.acquire_object("base_projectile")
	if proj != null:
		proj.global_position = global_position
		if proj.has_method("setup"):
			proj.setup(data.base_damage, dir, custom_speed, data.attack_range)
		
		# Agiongiamo alla scena principale per evitare offset parentali
		if proj.get_parent() == null:
			get_tree().current_scene.add_child(proj)
