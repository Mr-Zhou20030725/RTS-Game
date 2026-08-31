class_name RangedAttackComponent
extends Node

## Reusable ranged attack behavior. Formal targeting priorities arrive in T08.

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
@export var projectile_spawn_offset := Vector2.ZERO
@export var projectile_scene: PackedScene = DEFAULT_PROJECTILE_SCENE
@export var target_group: StringName = &"combat_targets"

var current_target: Node2D
var _attack_cooldown := 0.0

@onready var actor := get_parent() as Node2D


func _ready() -> void:
	_attack_cooldown = attack_interval


func _physics_process(delta: float) -> void:
	if not combat_enabled or actor == null:
		return

	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	if not _is_target_in_range(current_target):
		_set_target(_find_nearest_hostile_target())
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

	projectile.call("configure", actor, target, attack_damage, projectile_speed)
	projectile_parent.add_child(projectile)
	projectile.global_position = actor.global_position + projectile_spawn_offset
	_attack_cooldown = attack_interval
	projectile_fired.emit(projectile, target)
	return projectile


func _find_nearest_hostile_target() -> Node2D:
	var nearest_target: Node2D
	var nearest_distance := INF
	for candidate_node in get_tree().get_nodes_in_group(target_group):
		if candidate_node == actor or not candidate_node is Node2D:
			continue
		var candidate := candidate_node as Node2D
		if not _is_target_in_range(candidate):
			continue
		var distance := actor.global_position.distance_to(candidate.global_position)
		if distance < nearest_distance:
			nearest_target = candidate
			nearest_distance = distance
	return nearest_target


func _is_target_in_range(target: Node2D) -> bool:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return false
	if not CombatRules.can_damage(actor, target):
		return false
	return actor.global_position.distance_to(target.global_position) <= attack_range


func _set_target(target: Node2D) -> void:
	if current_target == target:
		return
	current_target = target
	target_changed.emit(current_target)
