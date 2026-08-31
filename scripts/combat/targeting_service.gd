class_name TargetingService
extends RefCounted

## Shared, deterministic target validation and ranking for combat components.

enum PriorityMode {
	NEAREST,
	UNITS_FIRST,
	BUILDINGS_FIRST,
}

const UNIT_GROUP: StringName = &"combat_units"
const BUILDING_GROUP: StringName = &"combat_buildings"


static func find_best_target_in_group(
	actor: Node2D,
	target_group: StringName,
	max_range: float,
	priority_mode: PriorityMode = PriorityMode.NEAREST
) -> Node2D:
	if actor == null or not is_instance_valid(actor) or not actor.is_inside_tree():
		return null
	return find_best_target(
		actor,
		actor.get_tree().get_nodes_in_group(target_group),
		max_range,
		priority_mode
	)


static func find_best_target(
	actor: Node2D,
	candidates: Array,
	max_range: float,
	priority_mode: PriorityMode = PriorityMode.NEAREST
) -> Node2D:
	var best_target: Node2D
	var best_category_priority := 999
	var best_distance_squared := INF
	var best_instance_id := 0
	var safe_range := maxf(max_range, 0.0)

	for candidate_node in candidates:
		if not candidate_node is Node2D:
			continue
		var candidate := candidate_node as Node2D
		if not is_valid_target(actor, candidate, safe_range):
			continue

		var category_priority := _get_category_priority(
			candidate, priority_mode
		)
		var distance_squared := actor.global_position.distance_squared_to(
			candidate.global_position
		)
		var instance_id := candidate.get_instance_id()
		if (
			category_priority < best_category_priority
			or (
				category_priority == best_category_priority
				and distance_squared < best_distance_squared
			)
			or (
				category_priority == best_category_priority
				and is_equal_approx(distance_squared, best_distance_squared)
				and (best_target == null or instance_id < best_instance_id)
			)
		):
			best_target = candidate
			best_category_priority = category_priority
			best_distance_squared = distance_squared
			best_instance_id = instance_id

	return best_target


static func is_valid_target(
	actor: Node2D, target: Node2D, max_range: float = INF
) -> bool:
	if actor == null or target == null or actor == target:
		return false
	if not is_instance_valid(target) or not target.is_inside_tree():
		return false
	if not CombatRules.can_damage(actor, target):
		return false

	var health := target.get_node_or_null("HealthComponent") as HealthComponent
	if health == null or health.is_dead:
		return false
	return actor.global_position.distance_to(target.global_position) <= max_range


static func _get_category_priority(
	target: Node2D, priority_mode: PriorityMode
) -> int:
	match priority_mode:
		PriorityMode.UNITS_FIRST:
			if target.is_in_group(UNIT_GROUP):
				return 0
			if target.is_in_group(BUILDING_GROUP):
				return 2
			return 1
		PriorityMode.BUILDINGS_FIRST:
			if target.is_in_group(BUILDING_GROUP):
				return 0
			if target.is_in_group(UNIT_GROUP):
				return 2
			return 1
		_:
			return 0
