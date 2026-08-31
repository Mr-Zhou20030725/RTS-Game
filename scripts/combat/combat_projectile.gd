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


func configure(
	attacker: Node,
	target: Node2D,
	configured_damage: float,
	configured_speed: float
) -> void:
	_attacker_ref = weakref(attacker)
	_target_ref = weakref(target)
	damage = maxf(configured_damage, 0.0)
	projectile_speed = maxf(configured_speed, 1.0)
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
		var applied_damage := CombatRules.try_apply_damage(
			attacker, target, damage
		)
		hit.emit(target, applied_damage)
		queue_free()
		return

	global_position += global_position.direction_to(
		target.global_position
	) * travel_distance
	rotation = global_position.direction_to(target.global_position).angle()


func get_target() -> Node2D:
	return _get_target()


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
