class_name WaveManager
extends Node

## Manages procedurally generated waves using a 'Wave Budget' algorithm.
## Attach this node to a level/spawner node.

@export var base_budget_per_wave: float = 100.0
@export var budget_multiplier: float = 1.15

## Time between enemies spawning during an active wave
@export var spawn_interval: float = 1.0

var current_wave: int = 1
var is_wave_active: bool = false
var enemies_left_to_spawn: int = 0
var active_enemies: int = 0

## The active budget left to spend for the current wave
var _current_budget: float = 0.0

@onready var spawn_timer: Timer = Timer.new()

func _ready() -> void:
	# Setup spawn timer using signal up call down (timer -> self -> spawn logic)
	spawn_timer.wait_time = spawn_interval
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(spawn_timer)
	
	# Listen to death events via the Event Bus for decrementing active enemies
	Events.enemy_died.connect(_on_enemy_died)

## Initiates the next wave, calculating budget and starting the spawn timer
func start_next_wave() -> void:
	if is_wave_active: return
	is_wave_active = true
	
	_current_budget = base_budget_per_wave * pow(budget_multiplier, current_wave - 1)
	_calculate_spawns_for_budget()
	
	Events.wave_started.emit(current_wave)
	spawn_timer.start()

## Calculate how many enemies (and what types) will spawn based on budget
func _calculate_spawns_for_budget() -> void:
	# Basic implementation: 
	# Assume we have 1 simple enemy right now costing 10 budget points.
	# In a real scenario, you iterate over an array of EnemyStats Resources, 
	# picking combinations until budget hits 0.
	var default_enemy_cost: float = 10.0
	enemies_left_to_spawn = int(_current_budget / default_enemy_cost)
	
	# Minimal spawn amount even on low budget
	if enemies_left_to_spawn <= 0:
		enemies_left_to_spawn = 1

func _on_spawn_timer_timeout() -> void:
	if enemies_left_to_spawn > 0:
		# We spawn an enemy here
		_spawn_enemy()
		enemies_left_to_spawn -= 1
	else:
		# Stop spawning when budget is empty
		spawn_timer.stop()

func _spawn_enemy() -> void:
	# Request an enemy from the object pool for performance
	var enemy: Node = ObjectPool.acquire_object("common_enemy")
	if enemy != null:
		# Position logic can be injected here or handled by the parent
		Events.enemy_spawned.emit(enemy)
		active_enemies += 1

func _on_enemy_died(enemy: Node2D, _gold_reward: int) -> void:
	# Release back to pool to stop processing and hide visual
	ObjectPool.release_object("common_enemy", enemy)
	
	active_enemies -= 1
	
	if enemies_left_to_spawn <= 0 and active_enemies <= 0:
		_wave_completed()

func _wave_completed() -> void:
	is_wave_active = false
	Events.wave_completed.emit(current_wave)
	current_wave += 1
