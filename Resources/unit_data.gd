class_name UnitData
extends Resource

## Represents the structural data of a single summonable/mergable unit.
## Define different units by creating .tres files referencing this script.

@export var unit_id: StringName = ""
@export var display_name: String = "Unknown Unit"
@export var footprint: Vector2i = Vector2i(1, 1)

enum AbilityType { NORMAL, TWIN_SIDES, FLAMETHROWER, QUAKE, WALL }
@export var ability: AbilityType = AbilityType.NORMAL

@export var tier: int = 1
@export var base_damage: float = 10.0
@export var attack_speed: float = 1.0
@export var attack_range: float = 150.0

@export_group("Visuals")
@export var sprite_texture: Texture2D
@export var projectile_scene: PackedScene

@export_group("Merging Setup")
## The UnitData Resource that should be spawned if two of these are merged.
## Leave null if this is the max tier.
@export var next_tier_data: UnitData

## Called by external systems to verify if this unit can merge with another unit
func can_merge_with(other_data: UnitData) -> bool:
	if other_data == null:
		return false
	# Can only merge if IDs match, and we have a next tier to upgrade to.
	return unit_id == other_data.unit_id and next_tier_data != null
