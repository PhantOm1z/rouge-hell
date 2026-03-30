class_name WaveManager
extends Node

@export var max_waves: int = 5
@export var base_budget_per_wave: float = 40.0
@export var budget_multiplier: float = 1.3
@export var spawn_interval: float = 0.8

var current_wave: int = 1
var is_wave_active: bool = false
var enemies_left_to_spawn: int = 0
var active_enemies: int = 0
var _current_budget: float = 0.0

@onready var spawn_timer: Timer = Timer.new()

# Caricamento dinamico dei dati
var enemy_types: Array[Resource] = [
	preload("res://Resources/enemy_data.gd").new(), # Base (auto-valorizzato a 50hp/40spd dalla classe)
	preload("res://Resources/Instances/fast_enemy.tres"),
	preload("res://Resources/Instances/tank_enemy.tres")
]

func _ready() -> void:
	spawn_timer.wait_time = spawn_interval
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(spawn_timer)
	Events.enemy_died.connect(_on_enemy_died)

func start_next_wave() -> void:
	if is_wave_active: return
	if current_wave > max_waves:
		print("VITTORIA! TUTTE LE 5 WAVES COMPLETATE")
		return
		
	is_wave_active = true
	_current_budget = base_budget_per_wave * pow(budget_multiplier, current_wave - 1)
	
	# Più andiamo avanti, più il budget compra nemici e più variano
	var default_enemy_cost: float = 10.0
	enemies_left_to_spawn = max(1, int(_current_budget / default_enemy_cost))
	
	Events.wave_started.emit(current_wave)
	spawn_timer.start()

func _on_spawn_timer_timeout() -> void:
	if enemies_left_to_spawn > 0:
		_spawn_enemy()
		enemies_left_to_spawn -= 1
	else:
		spawn_timer.stop()

func _spawn_enemy() -> void:
	# Il tool di ObjectPool tira fuori un'istanza riutilizzabile del nemico
	var enemy: Node = ObjectPool.acquire_object("common_enemy")
	if enemy != null:
		# Posizione: Sopra la griglia (Global Y tra -50 e 100), Random X da 50 a 650
		var spawn_pos = Vector2(randf_range(50.0, 650.0), -50)
		enemy.global_position = spawn_pos
		
		# Scegliamo dati nemico in base al livello della wave (Wave 1 solo base, Wave 3 veloci, Wave 5 tank)
		var chosen_data: EnemyData
		if current_wave == 5:
			# Il gran finale: SPAWNA SOLO IL BOSS INFERNALE (1 solo in tutta la wave)
			chosen_data = preload("res://Resources/Instances/boss_enemy.tres")
			enemies_left_to_spawn = 0 # Blocca la coda di spawn
		elif current_wave <= 2:
			chosen_data = enemy_types[0] # Base
		elif current_wave <= 4:
			chosen_data = enemy_types.pick_random() # Base o Veloce
		else:
			chosen_data = enemy_types[2] # Introduce Tank
			
		enemy.setup(chosen_data)
		
		# Target IA: vanno verso il fuoco della Base! 
		# Global target del cuore del PlayerBase è circa Vector2(360, 1078)
		if enemy.has_method("set_path_points"):
			var base_pos = Vector2(360, 1080)
			enemy.set_path_points(PackedVector2Array([base_pos]))
			
		Events.call_deferred("emit_signal", "enemy_spawned", enemy)
		active_enemies += 1

func _on_enemy_died(enemy: Node2D, gold_reward: int) -> void:
	ObjectPool.release_object("common_enemy", enemy)
	active_enemies -= 1
	
	if enemies_left_to_spawn <= 0 and active_enemies <= 0:
		_wave_completed()

func _wave_completed() -> void:
	is_wave_active = false
	Events.wave_completed.emit(current_wave)
	print("WAVE ", current_wave, " COMPLETATA VITTORIOSAMENTE!")
	current_wave += 1
	
	# Riposo 3 secondi poi parte la successiva
	await get_tree().create_timer(3.0).timeout
	start_next_wave()
