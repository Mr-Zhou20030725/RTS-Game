class_name RTSUnit
extends CharacterBody2D

## Minimal movable and selectable RTS unit used by T04.

signal waypoint_reached(unit: Node2D, world_position: Vector2)
signal waypoint_route_changed(unit: Node2D)

@export var move_speed := 150.0
@export var selection_radius := 24.0
@export var arrival_distance := 10.0
@export var separation_distance := 42.0
@export var separation_strength := 110.0

@onready var navigation_agent: NavigationAgent2D = %NavigationAgent2D
@onready var selection_indicator: Line2D = %SelectionIndicator
@onready var collision_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
@onready var health_component := get_node_or_null(
	"HealthComponent"
) as HealthComponent
@onready var melee_component := get_node_or_null(
	"MeleeAttackComponent"
) as MeleeAttackComponent
@onready var ranged_component := get_node_or_null("RangedAttackComponent")

var is_selected := false
var _has_move_target := false
var _move_target := Vector2.ZERO
var _manual_move_order_active := false
var _movement_slow_multiplier := 1.0
var _movement_slow_remaining := 0.0
var _waypoint_route_active := false
var _waypoint_queue: Array[Vector2] = []
var _route_attack_target: Node2D


func _ready() -> void:
	selection_indicator.visible = is_selected
	if health_component != null:
		health_component.died.connect(_on_died)


func _physics_process(delta: float) -> void:
	_update_movement_slow(delta)
	if not _has_move_target:
		velocity = Vector2.ZERO
		return

	if (
		NavigationServer2D.map_get_iteration_id(
			navigation_agent.get_navigation_map()
		)
		== 0
	):
		velocity = Vector2.ZERO
		return

	if global_position.distance_to(_move_target) <= arrival_distance:
		if _complete_current_waypoint():
			return
		stop_moving()
		return

	var next_path_position := navigation_agent.get_next_path_position()
	var movement_direction := global_position.direction_to(next_path_position)
	if movement_direction.is_zero_approx():
		movement_direction = global_position.direction_to(_move_target)

	var effective_speed := get_effective_move_speed()
	var desired_velocity := movement_direction * effective_speed
	var separation_velocity := _calculate_separation_velocity()
	velocity = (desired_velocity + separation_velocity).limit_length(effective_speed)
	move_and_slide()


func set_selected(value: bool) -> void:
	is_selected = value
	selection_indicator.visible = value


func move_to(world_position: Vector2) -> void:
	_clear_waypoint_route()
	_clear_combat_targets()
	_manual_move_order_active = true
	_set_move_target(world_position)


func move_to_combat_target(world_position: Vector2) -> void:
	_manual_move_order_active = false
	_set_move_target(world_position)


func attack_target(target: Node2D) -> bool:
	if target == null or not CombatRules.can_damage(self, target):
		return false
	_clear_waypoint_route()
	_clear_combat_targets()
	_manual_move_order_active = false
	if (
		melee_component != null
		and melee_component.combat_enabled
		and melee_component.has_method("set_command_target")
	):
		return melee_component.call("set_command_target", target)
	if (
		ranged_component != null
		and bool(ranged_component.get("combat_enabled"))
		and ranged_component.has_method("set_command_target")
	):
		return ranged_component.call("set_command_target", target)
	return false


func get_command_target() -> Node2D:
	if (
		melee_component != null
		and melee_component.combat_enabled
		and melee_component.has_method("get_command_target")
	):
		return melee_component.call("get_command_target") as Node2D
	if (
		ranged_component != null
		and bool(ranged_component.get("combat_enabled"))
		and ranged_component.has_method("get_command_target")
	):
		return ranged_component.call("get_command_target") as Node2D
	return null


func append_waypoint(world_position: Vector2) -> void:
	_clear_combat_targets()
	_manual_move_order_active = true
	_waypoint_route_active = true
	if _has_move_target:
		_waypoint_queue.append(world_position)
	else:
		_set_move_target(world_position)
	waypoint_route_changed.emit(self)


func append_route_attack_target(target: Node2D) -> bool:
	if target == null or not CombatRules.can_damage(self, target):
		return false
	if not _has_move_target and _waypoint_queue.is_empty():
		return attack_target(target)
	_clear_combat_targets()
	_manual_move_order_active = true
	_waypoint_route_active = true
	_route_attack_target = target
	waypoint_route_changed.emit(self)
	return true


func get_waypoint_route() -> Array[Vector2]:
	var result: Array[Vector2] = []
	if _waypoint_route_active and _has_move_target:
		result.append(_move_target)
	result.append_array(_waypoint_queue)
	return result


func get_route_attack_target() -> Node2D:
	if not is_instance_valid(_route_attack_target):
		_route_attack_target = null
	return _route_attack_target


func has_waypoint_route() -> bool:
	return (
		_waypoint_route_active
		and (_has_move_target or not _waypoint_queue.is_empty())
	)


func is_manual_move_order_active() -> bool:
	return _manual_move_order_active


func _set_move_target(world_position: Vector2) -> void:
	_move_target = world_position
	_has_move_target = true
	navigation_agent.target_position = world_position


func get_move_target() -> Vector2:
	return _move_target


func has_move_target() -> bool:
	return _has_move_target


func get_selection_radius() -> float:
	return selection_radius


func stop_moving() -> void:
	_has_move_target = false
	_manual_move_order_active = false
	velocity = Vector2.ZERO
	_clear_waypoint_route()


func _clear_combat_targets() -> void:
	if melee_component != null:
		melee_component.clear_target()
	if ranged_component != null and ranged_component.has_method("clear_target"):
		ranged_component.call("clear_target")


func _complete_current_waypoint() -> bool:
	if not _waypoint_route_active:
		return false
	waypoint_reached.emit(self, _move_target)
	if not _waypoint_queue.is_empty():
		_set_move_target(_waypoint_queue.pop_front())
		_manual_move_order_active = true
		waypoint_route_changed.emit(self)
		return true
	var final_target := get_route_attack_target()
	_waypoint_route_active = false
	_route_attack_target = null
	_has_move_target = false
	waypoint_route_changed.emit(self)
	if final_target != null and attack_target(final_target):
		return true
	return false


func _clear_waypoint_route() -> void:
	var had_route := (
		_waypoint_route_active
		or not _waypoint_queue.is_empty()
		or _route_attack_target != null
	)
	_waypoint_route_active = false
	_waypoint_queue.clear()
	_route_attack_target = null
	if had_route:
		waypoint_route_changed.emit(self)


func apply_movement_slow(multiplier: float, duration: float) -> bool:
	if multiplier >= 1.0 or multiplier <= 0.0 or duration <= 0.0:
		return false
	if health_component != null and health_component.is_dead:
		return false
	_movement_slow_multiplier = minf(
		_movement_slow_multiplier, clampf(multiplier, 0.1, 1.0)
	)
	_movement_slow_remaining = maxf(_movement_slow_remaining, duration)
	return true


func get_effective_move_speed() -> float:
	return move_speed * _movement_slow_multiplier


func get_movement_slow_remaining() -> float:
	return _movement_slow_remaining


func _update_movement_slow(delta: float) -> void:
	if _movement_slow_remaining <= 0.0:
		return
	_movement_slow_remaining = maxf(_movement_slow_remaining - delta, 0.0)
	if is_zero_approx(_movement_slow_remaining):
		_movement_slow_multiplier = 1.0


func _calculate_separation_velocity() -> Vector2:
	var separation := Vector2.ZERO
	for other_node in get_tree().get_nodes_in_group("moving_units"):
		if other_node == self or not other_node is Node2D:
			continue

		var other := other_node as Node2D
		var offset: Vector2 = global_position - other.global_position
		var distance: float = offset.length()
		if distance <= 0.001:
			var fallback_angle := float(get_instance_id() % 360)
			offset = Vector2.RIGHT.rotated(deg_to_rad(fallback_angle))
			distance = 1.0
		if distance >= separation_distance:
			continue

		var strength: float = 1.0 - (distance / separation_distance)
		separation += offset.normalized() * separation_strength * strength
	return separation


func _on_died(_source: Node) -> void:
	stop_moving()
	set_selected(false)
	for group_name in [
		&"combat_targets",
		&"moving_units",
		&"selectable_units",
	]:
		if is_in_group(group_name):
			remove_from_group(group_name)
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	if melee_component != null:
		melee_component.combat_enabled = false
	if ranged_component != null:
		ranged_component.set("combat_enabled", false)
	if collision_shape != null:
		collision_shape.set_deferred("disabled", true)
	modulate = Color(0.35, 0.35, 0.35, 0.65)
