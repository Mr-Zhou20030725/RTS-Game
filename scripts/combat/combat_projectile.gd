class_name CombatProjectile
extends Node2D

## Lightweight homing projectile that safely expires with an invalid target.

signal hit(target: Node2D, applied_damage: float)
signal expired

@export_range(1.0, 5000.0, 1.0) var projectile_speed := 450.0
@export_range(0.1, 100000.0, 0.1) var damage := 10.0
@export_range(1.0, 100.0, 1.0) var hit_radius := 8.0
@export_range(0.1, 30.0, 0.1) var max_lifetime := 6.0

var _attacker_ref: WeakRef
var _target_ref: WeakRef
var _lifetime_remaining := 0.0
var _is_configured := false
var _splash_radius := 0.0
var _slow_multiplier := 1.0
var _slow_duration := 0.0
var _target_group: StringName = &"combat_targets"


func configure(
	attacker: Node,
	target: Node2D,
	configured_damage: float,
	configured_speed: float,
	configured_splash_radius: float = 0.0,
	configured_slow_multiplier: float = 1.0,
	configured_slow_duration: float = 0.0,
	configured_target_group: StringName = &"combat_targets"
) -> void:
	_attacker_ref = weakref(attacker)
	_target_ref = weakref(target)
	damage = maxf(configured_damage, 0.0)
	projectile_speed = maxf(configured_speed, 1.0)
	_splash_radius = maxf(configured_splash_radius, 0.0)
	_slow_multiplier = clampf(configured_slow_multiplier, 0.1, 1.0)
	_slow_duration = maxf(configured_slow_duration, 0.0)
	_target_group = configured_target_group
	_lifetime_remaining = max_lifetime
	_is_configured = true


func _physics_process(delta: float) -> void:
	if not _is_configured:
		return

	_lifetime_remaining -= delta
	if _lifetime_remaining <= 0.0:
		_expire()
		return

	var attacker := _get_attacker()
	var target := _get_target()
	if attacker == null or target == null:
		_expire()
		return
	if not CombatRules.can_damage(attacker, target):
		_expire()
		return

	var distance_to_target := global_position.distance_to(target.global_position)
	var travel_distance := projectile_speed * delta
	if distance_to_target <= maxf(hit_radius, travel_distance):
		global_position = target.global_position
		var applied_damage := _apply_hit(attacker, target)
		hit.emit(target, applied_damage)
		queue_free()
		return

	global_position += global_position.direction_to(
		target.global_position
	) * travel_distance
	rotation = global_position.direction_to(target.global_position).angle()


func get_target() -> Node2D:
	return _get_target()


func _apply_hit(attacker: Node, primary_target: Node2D) -> float:
	var impact_position := primary_target.global_position
	var primary_damage := CombatRules.try_apply_damage(
		attacker, primary_target, damage
	)
	_apply_slow(primary_target)

	if _splash_radius <= 0.0:
		return primary_damage
	for candidate_node in get_tree().get_nodes_in_group(_target_group):
		if candidate_node == primary_target or not candidate_node is Node2D:
			continue
		var candidate := candidate_node as Node2D
		if candidate.global_position.distance_to(impact_position) > _splash_radius:
			continue
		if CombatRules.try_apply_damage(attacker, candidate, damage) > 0.0:
			_apply_slow(candidate)
	return primary_damage


func _apply_slow(target: Node2D) -> void:
	if (
		_slow_multiplier >= 1.0
		or _slow_duration <= 0.0
		or not target.has_method("apply_movement_slow")
	):
		return
	var health := target.get_node_or_null("HealthComponent") as HealthComponent
	if health != null and not health.is_dead:
		target.call(
			"apply_movement_slow", _slow_multiplier, _slow_duration
		)


func _get_attacker() -> Node:
	if _attacker_ref == null:
		return null
	var attacker := _attacker_ref.get_ref() as Node
	if attacker == null or not is_instance_valid(attacker):
		return null
	return attacker


func _get_target() -> Node2D:
	if _target_ref == null:
		return null
	var target := _target_ref.get_ref() as Node2D
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return null
	return target


func _expire() -> void:
	expired.emit()
	queue_free()
