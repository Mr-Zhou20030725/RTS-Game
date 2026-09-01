class_name MeleeAttackComponent
extends Node

## Reusable melee attack, chase, and reacquisition behavior.

const TargetSelector := preload("res://scripts/combat/targeting_service.gd")

signal target_changed(target: Node2D)
signal attack_performed(target: Node2D, applied_damage: float)

@export var combat_enabled := true
@export_range(0.1, 100000.0, 0.1) var attack_damage := 20.0
@export_range(0.05, 60.0, 0.05) var attack_interval := 0.6
@export_range(1.0, 1000.0, 1.0) var attack_range := 42.0
@export_range(1.0, 2000.0, 1.0) var acquisition_range := 260.0
@export_range(1.0, 3000.0, 1.0) var chase_range := 380.0
@export_range(0.05, 2.0, 0.05) var repath_interval := 0.2
@export var target_group: StringName = &"combat_targets"
@export_enum("Nearest", "Units First", "Buildings First") var target_priority := 0

var current_target: Node2D
var _attack_cooldown := 0.0
var _repath_cooldown := 0.0
var _last_chase_position := Vector2.INF
var _was_chasing := false

@onready var actor := get_parent() as Node2D


func _ready() -> void:
	_attack_cooldown = attack_interval


func _physics_process(delta: float) -> void:
	if not combat_enabled or actor == null:
		return
	_clear_freed_target()
	if _has_manual_move_order():
		if current_target != null:
			_clear_target(false)
		return

	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	_repath_cooldown = maxf(_repath_cooldown - delta, 0.0)

	if not _is_target_valid(current_target):
		_set_target(_find_best_hostile_target())

	if current_target == null:
		return

	var distance_to_target := actor.global_position.distance_to(
		current_target.global_position
	)
	if distance_to_target > chase_range:
		_clear_target(true)
		return

	if distance_to_target <= attack_range:
		_stop_actor()
		_was_chasing = false
		if is_zero_approx(_attack_cooldown):
			_perform_attack()
		return

	_chase_current_target()


func get_current_target() -> Node2D:
	return current_target


func clear_target() -> void:
	_clear_target(true)


func _find_best_hostile_target() -> Node2D:
	return TargetSelector.find_best_target_in_group(
		actor, target_group, acquisition_range, target_priority
	)


func _chase_current_target() -> void:
	if not actor.has_method("move_to_combat_target"):
		_clear_target(false)
		return

	var target_position := current_target.global_position
	if (
		_repath_cooldown > 0.0
		and target_position.distance_to(_last_chase_position) < 8.0
	):
		return

	actor.call("move_to_combat_target", target_position)
	_last_chase_position = target_position
	_repath_cooldown = repath_interval
	_was_chasing = true


func _perform_attack() -> void:
	if not _is_target_valid(current_target):
		_clear_target(false)
		return

	var attacked_target := current_target
	var applied_damage := CombatRules.try_apply_damage(
		actor, attacked_target, attack_damage
	)
	_attack_cooldown = attack_interval
	if applied_damage > 0.0:
		attack_performed.emit(attacked_target, applied_damage)

	if not _is_target_valid(attacked_target):
		_set_target(null)


func _is_target_valid(target: Node2D) -> bool:
	return TargetSelector.is_valid_target(actor, target)


func _set_target(target: Node2D) -> void:
	if current_target == target:
		return
	current_target = target
	_last_chase_position = Vector2.INF
	_repath_cooldown = 0.0
	target_changed.emit(current_target)


func _clear_target(stop_actor: bool) -> void:
	_set_target(null)
	if stop_actor and _was_chasing:
		_stop_actor()
	_was_chasing = false


func _stop_actor() -> void:
	if actor.has_method("stop_moving"):
		actor.call("stop_moving")


func _has_manual_move_order() -> bool:
	return (
		actor.has_method("is_manual_move_order_active")
		and actor.call("is_manual_move_order_active")
	)


func _clear_freed_target() -> void:
	if is_instance_valid(current_target):
		return
	current_target = null
	_last_chase_position = Vector2.INF
	_repath_cooldown = 0.0
	_was_chasing = false
