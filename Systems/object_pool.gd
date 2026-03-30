extends Node

# Systems/ObjectPool.gd
# Autoload (Singleton)

## Object Pooling implementation to avoid GC spikes on Android.
## This handles projectiles, damage numbers, and common enemies.

var _pools: Dictionary = {}

## Call this on startup to warm up pools.
func register_pool(pool_name: StringName, scene: PackedScene, initial_size: int = 10) -> void:
    if not _pools.has(pool_name):
        _pools[pool_name] = {
            "scene": scene,
            "active": [],
            "inactive": []
        }
    
    # Pre-instantiate objects
    for i in range(initial_size):
        var instance: Node = scene.instantiate()
        _setup_instance_for_pool(instance, pool_name)
        _pools[pool_name]["inactive"].append(instance)
        add_child(instance)
        _disable_instance(instance)

## Gets an object from the pool. Creates a new one if the pool is empty.
func acquire_object(pool_name: StringName) -> Node:
    if not _pools.has(pool_name):
        push_error("Pool %s not registered." % pool_name)
        return null

    var pool: Dictionary = _pools[pool_name]
    var instance: Node

    if pool["inactive"].size() > 0:
        instance = pool["inactive"].pop_back()
    else:
        # Expand pool if needed (could log this if debugging memory spikes)
        instance = pool["scene"].instantiate()
        _setup_instance_for_pool(instance, pool_name)
        add_child(instance)

    pool["active"].append(instance)
    _enable_instance(instance)
    
    # Optionally reset specific state here or let the acquirer do it
    return instance

## Returns an object back to its pool
func release_object(pool_name: StringName, instance: Node) -> void:
    if not _pools.has(pool_name):
        push_error("Pool %s not valid for release." % pool_name)
        instance.queue_free()
        return

    var pool: Dictionary = _pools[pool_name]
    if instance in pool["active"]:
        pool["active"].erase(instance)
        
        # Reset visual state and disable computation
        _disable_instance(instance)
        pool["inactive"].append(instance)

## Attaches meta to remember its pool origin
func _setup_instance_for_pool(instance: Node, pool_name: StringName) -> void:
    # Adding as meta makes it easier for the projectile itself to know where it came from
    instance.set_meta("pool_origin", pool_name)

## Completely disables processing/drawing for inactive objects
func _disable_instance(instance: Node) -> void:
    instance.set_process(false)
    instance.set_physics_process(false)
    
    if instance is Node2D:
        instance.hide()
        
    # Standard GDScript 2.0 idiom to disable physics processing for bodies/areas
    if instance is CollisionObject2D:
        # Disable all collision masking/layers by storing old state OR setting disable_mode
        instance.set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)

## Re-enables generic processing
func _enable_instance(instance: Node) -> void:
    instance.set_process(true)
    instance.set_physics_process(true)
    
    if instance is Node2D:
        instance.show()
        
    if instance is CollisionObject2D:
        instance.set_deferred("process_mode", Node.PROCESS_MODE_INHERIT)
