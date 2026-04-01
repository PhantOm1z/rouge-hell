extends Node

# Globals/Events.gd
# Autoload (Singleton)

# --- Game State Signals ---
signal game_started
signal game_over
signal wave_started(wave_index: int)
signal wave_completed(wave_index: int)

# --- Currency / Resource Signals ---
signal gold_changed(new_amount: int)
signal gem_changed(new_amount: int)

# --- Combat Signals ---
signal enemy_spawned(enemy: Node2D)
signal enemy_died(enemy: Node2D, gold_reward: int)
signal base_damaged(amount: int)

# --- Grid & Unit Signals ---
signal unit_summoned(grid_pos: Vector2i, unit: Node2D)
signal unit_merged(grid_pos: Vector2i, new_unit_data: Resource)
signal cell_selected(grid_pos: Vector2i)

# --- UI / Deck Signals ---
signal card_dropped(card_ui: Control, drop_pos: Vector2)
signal card_dragged(card_ui: Control, drag_pos: Vector2)
signal card_drag_ended(card_ui: Control)
signal select_draft_card(unit_data: Resource)
signal grid_updated()

# --- RPG Progression ---
signal exp_gained(amount: int)
signal level_up(new_level: int)
