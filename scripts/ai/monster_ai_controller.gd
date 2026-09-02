class_name MonsterAIController
extends Node

## Rule AI: builds Monster waves and attacks relatively weak Human sectors.

signal ai_enabled_changed(is_enabled: bool)
signal defense_analysis_updated(scores: Dictionary)
signal ai_monster_produced(monster: Node2D, nest: Node2D, catalog_index: int)
signal attack_wave_launched(
	direction: AttackDirection, units: Array[Node2D], target: Node2D
)

enum AttackDirection {
	NORTH,
	EAST,
	SOUTH,
	WEST,
}

const DIRECTION_VECTORS := [
	Vector2.UP,
	Vector2.RIGHT,
	Vector2.DOWN,
	Vector2.LEFT,
]
const DIRECTION_NAMES := ["北方", "东方", "南方", "西方"]

@export var config: MonsterAIConfig
@export var ai_enabled := true

var monster_economy: MonsterEconomy
var production_manager: MonsterProductionManager
var mvp_map: Node

var _production_elapsed := 0.0
var _attack_elapsed := 0.0
var _production_cursor := 0
var _direction_cursor := 0
var _last_direction := -1
var _same_direction_count := 0
var _direction_pressure: Dictionary[int, float] = {}
var _last_defense_scores: Dictionary[int, float] = {}
var _direction_history: Array[int] = []
var _production_attempt_count := 0
var _analysis_count := 0


func _ready() -> void:
	add_to_group(&"monster_ai_controller")
	for direction in AttackDirection.values():
		_direction_pressure[direction] = 0.0
		_last_defense_scores[direction] = 0.0
	call_deferred("_bind_dependencies")


func _process(delta: float) -> void:
	advance_simulation(delta)


func set_ai_enabled(value: bool) -> void:
	if ai_enabled == value:
		return
	ai_enabled = value
	ai_enabled_changed.emit(ai_enabled)


func is_ai_enabled() -> bool:
	return ai_enabled


func advance_simulation(delta: float) -> void:
	if not ai_enabled or config == null or delta <= 0.0:
		return
	_bind_dependencies()
	_production_elapsed += delta
	_attack_elapsed += delta
	var production_cycles := 0
	while (
		_production_elapsed >= config.production_interval
		and production_cycles < config.maximum_catch_up_cycles
	):
		_production_elapsed -= config.production_interval
		_production_attempt_count += 1
		run_production_cycle()
		production_cycles += 1
	if production_cycles == config.maximum_catch_up_cycles:
		_production_elapsed = fmod(_production_elapsed, config.production_interval)

	var attack_cycles := 0
	while (
		_attack_elapsed >= config.attack_interval
		and attack_cycles < config.maximum_catch_up_cycles
	):
		_attack_elapsed -= config.attack_interval
		launch_attack_wave()
		attack_cycles += 1
	if attack_cycles == config.maximum_catch_up_cycles:
		_attack_elapsed = fmod(_attack_elapsed, config.attack_interval)


func analyze_defense_strengths() -> Dictionary[int, float]:
	_bind_dependencies()
	var scores: Dictionary[int, float] = {}
	for direction in AttackDirection.values():
		scores[direction] = 0.0
	var human_base := _get_human_base()
	if human_base == null:
		_last_defense_scores = scores
		return scores
	for group_name in [&"combat_units", &"placed_towers"]:
		for actor_node in get_tree().get_nodes_in_group(group_name):
			var actor := actor_node as Node2D
			if not _is_living_human(actor):
				continue
			var direction := _classify_direction(
				actor.global_position - human_base.global_position
			)
			scores[direction] += _calculate_defense_strength(actor)
	_last_defense_scores = scores.duplicate()
	_analysis_count += 1
	defense_analysis_updated.emit(_last_defense_scores.duplicate())
	return scores


func choose_attack_direction() -> AttackDirection:
	var scores := analyze_defense_strengths()
	var ranked: Array[int] = []
	for direction in AttackDirection.values():
		ranked.append(int(direction))
	ranked.sort_custom(
		func(first: int, second: int) -> bool:
			var first_value := scores[first] + _direction_pressure[first]
			var second_value := scores[second] + _direction_pressure[second]
			if is_equal_approx(first_value, second_value):
				return (
					(first - _direction_cursor + 4) % 4
					< (second - _direction_cursor + 4) % 4
				)
			return first_value < second_value
	)
	var chosen := ranked[0]
	if chosen == _last_direction and _same_direction_count >= 2:
		chosen = ranked[1]
	return chosen as AttackDirection


func run_production_cycle() -> bool:
	_bind_dependencies()
	if (
		config == null
		or monster_economy == null
		or production_manager == null
		or mvp_map == null
		or _get_ai_monster_count() >= config.maximum_ai_monsters
	):
		return false
	var nests: Array[Node2D] = mvp_map.call("get_active_nests")
	if nests.is_empty() or config.production_rotation.is_empty():
		return false
	var catalog_index := _find_affordable_catalog_index()
	if catalog_index < 0:
		return false
	var direction := choose_attack_direction()
	var nest := _find_best_nest_for_direction(nests, direction)
	var before_count := production_manager.get_spawned_monsters().size()
	if not production_manager.produce_from_nest(catalog_index, nest):
		return false
	var monsters := production_manager.get_spawned_monsters()
	if monsters.size() <= before_count:
		return false
	var monster := monsters[monsters.size() - 1]
	monster.set_meta(&"ai_controlled", true)
	monster.set_meta(&"ai_wave_assigned", false)
	ai_monster_produced.emit(monster, nest, catalog_index)
	return true


func launch_attack_wave() -> bool:
	_bind_dependencies()
	if config == null:
		return false
	var idle_units := _get_idle_ai_monsters()
	if idle_units.size() < config.minimum_wave_size:
		return false
	var human_base := _get_human_base()
	if human_base == null:
		return false
	idle_units.sort_custom(
		func(first: Node2D, second: Node2D) -> bool:
			return first.get_instance_id() < second.get_instance_id()
	)
	var wave_units: Array[Node2D] = []
	for index in mini(idle_units.size(), config.maximum_wave_size):
		wave_units.append(idle_units[index])
	var direction := choose_attack_direction()
	var staging_center: Vector2 = human_base.global_position + (
		DIRECTION_VECTORS[direction] * config.staging_distance
	)
	staging_center.x = clampf(staging_center.x, 150.0, 3850.0)
	staging_center.y = clampf(staging_center.y, 150.0, 3850.0)
	var columns := int(ceil(sqrt(float(wave_units.size()))))
	for index in wave_units.size():
		var unit := wave_units[index]
		var column := index % columns
		var row := index / columns
		var offset := Vector2(
			(float(column) - float(columns - 1) * 0.5) * 38.0,
			float(row) * 38.0,
		)
		unit.call("append_waypoint", staging_center + offset)
		unit.call("append_route_attack_target", human_base)
		unit.set_meta(&"ai_wave_assigned", true)
		unit.set_meta(&"ai_attack_direction", direction)
	_update_direction_memory(direction)
	attack_wave_launched.emit(direction, wave_units, human_base)
	return true


func get_last_defense_scores() -> Dictionary[int, float]:
	return _last_defense_scores.duplicate()


func get_direction_history() -> Array[int]:
	return _direction_history.duplicate()


func get_production_attempt_count() -> int:
	return _production_attempt_count


func get_analysis_count() -> int:
	return _analysis_count


func get_direction_name(direction: AttackDirection) -> String:
	return DIRECTION_NAMES[direction]


func _bind_dependencies() -> void:
	if monster_economy == null or not is_instance_valid(monster_economy):
		monster_economy = get_tree().get_first_node_in_group(
			&"monster_economy"
		) as MonsterEconomy
	if production_manager == null or not is_instance_valid(production_manager):
		production_manager = get_tree().get_first_node_in_group(
			&"monster_production_manager"
		) as MonsterProductionManager
	if mvp_map == null or not is_instance_valid(mvp_map):
		mvp_map = get_tree().get_first_node_in_group(&"mvp_map")


func _find_affordable_catalog_index() -> int:
	var rotation_size := config.production_rotation.size()
	for offset in rotation_size:
		var rotation_index := (_production_cursor + offset) % rotation_size
		var catalog_index := config.production_rotation[rotation_index]
		var cost := production_manager.get_effective_cost(catalog_index)
		if cost >= 0 and monster_economy.can_afford(cost):
			_production_cursor = (rotation_index + 1) % rotation_size
			return catalog_index
	return -1


func _find_best_nest_for_direction(
	nests: Array[Node2D], direction: AttackDirection
) -> Node2D:
	var human_base := _get_human_base()
	if human_base == null:
		return nests[0]
	var staging: Vector2 = human_base.global_position + (
		DIRECTION_VECTORS[direction] * config.staging_distance
	)
	var best := nests[0]
	var best_distance := best.global_position.distance_squared_to(staging)
	for nest in nests:
		var distance := nest.global_position.distance_squared_to(staging)
		if distance < best_distance:
			best = nest
			best_distance = distance
	return best


func _get_idle_ai_monsters() -> Array[Node2D]:
	var result: Array[Node2D] = []
	if production_manager == null:
		return result
	for monster in production_manager.get_spawned_monsters():
		var health := monster.get_node_or_null("HealthComponent") as HealthComponent
		if (
			monster.get_meta(&"ai_controlled", false)
			and not monster.get_meta(&"ai_wave_assigned", false)
			and (health == null or not health.is_dead)
		):
			result.append(monster)
	return result


func _get_ai_monster_count() -> int:
	var count := 0
	if production_manager == null:
		return count
	for monster in production_manager.get_spawned_monsters():
		var health := monster.get_node_or_null("HealthComponent") as HealthComponent
		if (
			monster.get_meta(&"ai_controlled", false)
			and (health == null or not health.is_dead)
		):
			count += 1
	return count


func _get_human_base() -> Node2D:
	if mvp_map == null:
		return null
	var base := mvp_map.get("human_base") as Node2D
	if base == null or not is_instance_valid(base):
		return null
	var health := base.get_node_or_null("HealthComponent") as HealthComponent
	return null if health != null and health.is_dead else base


func _is_living_human(actor: Node2D) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	var faction := FactionComponent.find_on(actor)
	var health := actor.get_node_or_null("HealthComponent") as HealthComponent
	return (
		faction != null
		and faction.faction == FactionComponent.Faction.HUMAN
		and (health == null or not health.is_dead)
	)


func _calculate_defense_strength(actor: Node2D) -> float:
	var score := config.base_unit_strength
	var health := actor.get_node_or_null("HealthComponent") as HealthComponent
	if health != null:
		score += health.max_health * config.health_strength_weight
	var damage := 0.0
	var interval := 1.0
	var attack_range := 0.0
	if actor.has_method("get_tower_data"):
		var tower_data := actor.call("get_tower_data") as TowerData
		if tower_data != null:
			damage = tower_data.damage
			interval = tower_data.attack_interval
			attack_range = tower_data.attack_range
	elif actor.has_method("get_squad_data"):
		var squad_data := actor.call("get_squad_data") as HumanSquadData
		if squad_data != null:
			damage = squad_data.damage
			interval = squad_data.attack_interval
			attack_range = squad_data.attack_range
	score += (
		(damage / maxf(interval, 0.05)) * config.damage_per_second_weight
		+ attack_range * config.range_strength_weight
	)
	return score


func _classify_direction(offset: Vector2) -> AttackDirection:
	if absf(offset.x) > absf(offset.y):
		return AttackDirection.EAST if offset.x >= 0.0 else AttackDirection.WEST
	return AttackDirection.SOUTH if offset.y >= 0.0 else AttackDirection.NORTH


func _update_direction_memory(direction: AttackDirection) -> void:
	for direction_index in AttackDirection.values():
		_direction_pressure[direction_index] *= config.pressure_decay
	_direction_pressure[direction] += config.recent_direction_pressure
	if _last_direction == direction:
		_same_direction_count += 1
	else:
		_same_direction_count = 1
	_last_direction = direction
	_direction_cursor = (direction + 1) % 4
	_direction_history.append(direction)
	if _direction_history.size() > 32:
		_direction_history.pop_front()
