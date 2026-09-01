class_name RangedAttackComponent
extends Node

## Reusable ranged attack behavior with shared target prioritization.

const TargetSelector := preload("res://scripts/combat/targeting_service.gd")

signal target_changed(target: Node2D)
signal projectile_fired(projectile: Node2D, target: Node2D)

const DEFAULT_PROJECTILE_SCENE := preload(
	"res://scenes/combat/combat_projectile.tscn"
)

@export var combat_enabled := true
@export_range(0.1, 100000.0, 0.1) var attack_damage := 16.0
@export_range(0.05, 60.0, 0.05) var attack_interval := 0.8
@export_range(1.0, 2000.0, 1.0) var attack_range := 340.0
@export_range(1.0, 5000.0, 1.0) var projectile_speed := 450.0
@export_range(0.0, 1000.0, 1.0) var splash_radius := 0.0
@export_range(0.1, 1.0, 0.05) var slow_multiplier := 1.0
@export_range(0.0, 60.0, 0.1) var slow_duration := 0.0
@export var projectile_modulate := Color.WHITE
@export var projectile_spawn_offset := Vector2.ZERO
@export var projectile_scene: PackedScene = DEFAULT_PROJECTILE_SCENE
@export var target_group: StringName = &"combat_targets"
@export_enum("Nearest", "Units First", "Buildings First") var target_priority := 0

var current_target: Node2D
var _attack_cooldown := 0.0

@onready var actor := get_parent() as Node2D


func _ready() -> void:
	_attack_cooldown = attack_interval


func _physics_process(delta: float) -> void:
	if not combat_enabled or actor == null:
		return
	_clear_freed_target()
	if _has_manual_move_order():
		if current_target != null:
			_set_target(null)
		return

	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	if not _is_target_in_range(current_target):
		_set_target(_find_best_hostile_target())
	if current_target == null or not is_zero_approx(_attack_cooldown):
		return

	fire_at(current_target)


func get_current_target() -> Node2D:
	return current_target


func clear_target() -> void:
	_set_target(null)


func fire_at(target: Node2D) -> Node2D:
	if (
		not combat_enabled
		or actor == null
		or projectile_scene == null
		or not _is_target_in_range(target)
	):
		return null

	var projectile := projectile_scene.instantiate() as Node2D
	if projectile == null or not projectile.has_method("configure"):
		push_error("RangedAttackComponent requires a CombatProjectile scene.")
		if projectile != null:
			projectile.queue_free()
		return null

	var projectile_parent := actor.get_parent()
	if projectile_parent == null:
		projectile.queue_free()
		return null

	projectile.call(
		"configure",
		actor,
		target,
		attack_damage,
		projectile_speed,
		splash_radius,
		slow_multiplier,
		slow_duration,
		target_group
	)
	projectile_parent.add_child(projectile)
	projectile.global_position = actor.global_position + projectile_spawn_offset
	projectile.modulate = projectile_modulate
	_attack_cooldown = attack_interval
	projectile_fired.emit(projectile, target)
	return projectile


func _find_best_hostile_target() -> Node2D:
	return TargetSelector.find_best_target_in_group(
		actor, target_group, attack_range, target_priority
	)


func _is_target_in_range(target: Node2D) -> bool:
	return TargetSelector.is_valid_target(actor, target, attack_range)


func _set_target(target: Node2D) -> void:
	if current_target == target:
		return
	current_target = target
	target_changed.emit(current_target)


func _has_manual_move_order() -> bool:
	return (
		actor.has_method("is_manual_move_order_active")
		and actor.call("is_manual_move_order_active")
	)


func _clear_freed_target() -> void:
	if is_instance_valid(current_target):
		return
	current_target = null
