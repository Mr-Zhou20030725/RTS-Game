class_name HumanAIController
extends Node

## Rule AI: reacts to visible threats, builds a spread defense, and scouts.

signal ai_enabled_changed(is_enabled: bool)
signal threat_analysis_updated(scores: Dictionary)
signal ai_tower_built(
	tower: Node2D, direction: DefenseDirection, catalog_index: int
)
signal ai_squad_recruited(squad: Node2D, catalog_index: int)
signal defense_response_ordered(
	direction: DefenseDirection, units: Array[Node2D], target: Node2D
)
signal expedition_dispatched(
	direction: DefenseDirection,
	units: Array[Node2D],
	target: Node2D,
	destination: Vector2
)

enum DefenseDirection {
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
const DIRECTION_NAMES := ["NORTH", "EAST", "SOUTH", "WEST"]
const LATERAL_OFFSETS := [-64.0, 0.0, 64.0]

@export var config: HumanAIConfig
@export var ai_enabled := true

var human_economy: HumanEconomy
var placement_manager: BuildingPlacementManager
var squad_manager: HumanSquadManager
var fog_manager: FogOfWarManager
var mvp_map: Node

var _battle_elapsed := 0.0
var _analysis_elapsed := 0.0
var _build_elapsed := 0.0
var _recruit_elapsed := 0.0
var _expedition_elapsed := 0.0
var _tower_cursor := 0
var _squad_cursor := 0
var _balanced_direction_cursor := 0
var _exploration_cursor := 0
var _last_threat_scores: Dictionary[int, float] = {}
var _analysis_count := 0
var _expedition_count := 0


func _ready() -> void:
	add_to_group(&"human_ai_controller")
	for direction in DefenseDirection.values():
		_last_threat_scores[direction] = 0.0
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
	_battle_elapsed += delta
	_analysis_elapsed += delta
	_build_elapsed += delta
	_recruit_elapsed += delta
	_expedition_elapsed += delta
	_run_due_cycles(&"_analysis_elapsed", config.analysis_interval, run_analysis_cycle)
	_run_due_cycles(&"_build_elapsed", config.build_interval, run_build_cycle)
	_run_due_cycles(&"_recruit_elapsed", config.recruit_interval, run_recruit_cycle)
	_run_due_cycles(
		&"_expedition_elapsed", config.expedition_interval, run_expedition_cycle
	)


func analyze_visible_threats() -> Dictionary[int, float]:
	_bind_dependencies()
	var scores: Dictionary[int, float] = {}
	for direction in DefenseDirection.values():
		scores[direction] = 0.0
	var human_base := _get_human_base()
	if human_base == null:
		_last_threat_scores = scores
		return scores
	for monster in _get_visible_monsters():
		var distance := monster.global_position.distance_to(
			human_base.global_position
		)
		if distance > config.threat_scan_radius:
			continue
		var direction := _classify_direction(
			monster.global_position - human_base.global_position
		)
		var proximity := 1.0 - clampf(
			distance / config.threat_scan_radius, 0.0, 1.0
		)
		scores[direction] += _get_monster_threat(monster) * (
			1.0 + proximity
		)
	_last_threat_scores = scores.duplicate()
	_analysis_count += 1
	threat_analysis_updated.emit(_last_threat_scores.duplicate())
	return scores


func run_analysis_cycle() -> bool:
	var scores := analyze_visible_threats()
	var direction := _get_strongest_threat_direction(scores)
	if float(scores[direction]) < config.threat_response_threshold:
		return false
	return _respond_to_threat(direction)


func run_build_cycle() -> bool:
	_bind_dependencies()
	var living_towers := _get_living_towers()
	if (
		placement_manager == null
		or human_economy == null
		or living_towers.size() >= config.maximum_towers
		or config.tower_rotation.is_empty()
	):
		return false
	var scores := analyze_visible_threats()
	var strongest_direction := _get_strongest_threat_direction(scores)
	var threat_active := (
		float(scores[strongest_direction]) >= config.threat_response_threshold
	)
	var allowed_tower_lead := 3 if threat_active else 1
	if living_towers.size() >= _get_ai_squads().size() + allowed_tower_lead:
		return false
	var direction := _get_build_direction(scores)
	var tower_index := _find_affordable_tower_index()
	if tower_index < 0:
		return false
	for position in _get_build_candidates(direction):
		if not placement_manager.can_place_tower_at(tower_index, position):
			continue
		var tower := placement_manager.place_tower_at(tower_index, position)
		if tower == null:
			continue
		tower.set_meta(&"human_ai_controlled", true)
		tower.set_meta(&"human_ai_defense_direction", direction)
		_tower_cursor = (_tower_cursor + 1) % config.tower_rotation.size()
		ai_tower_built.emit(tower, direction, tower_index)
		return true
	return false


func run_recruit_cycle() -> bool:
	_bind_dependencies()
	if (
		squad_manager == null
		or human_economy == null
		or _get_ai_squads().size() >= config.maximum_squads
		or config.squad_rotation.is_empty()
	):
		return false
	var catalog_index := _find_affordable_squad_index()
	if catalog_index < 0 or not squad_manager.recruit_squad(catalog_index):
		return false
	var squad := squad_manager.get_latest_recruited_squad()
	if squad == null:
		return false
	squad.set_meta(&"human_ai_controlled", true)
	for child in squad.get_children():
		if child is Node2D:
			child.set_meta(&"human_ai_controlled", true)
	_squad_cursor = (_squad_cursor + 1) % config.squad_rotation.size()
	ai_squad_recruited.emit(squad, catalog_index)
	return true


func run_expedition_cycle() -> bool:
	_bind_dependencies()
	if (
		_battle_elapsed < config.midgame_start_time
		or _get_living_towers().size() < config.minimum_defense_towers
	):
		return false
	var units := _get_ai_members()
	if units.size() < config.minimum_expedition_members:
		return false
	var scores := analyze_visible_threats()
	var threat_direction := _get_strongest_threat_direction(scores)
	if float(scores[threat_direction]) >= config.threat_response_threshold:
		return false
	var visible_nest := _find_nearest_visible_nest(units[0].global_position)
	var direction := _exploration_cursor as DefenseDirection
	var destination := _get_exploration_point(direction)
	if visible_nest != null:
		direction = _classify_direction(
			visible_nest.global_position - _get_human_base().global_position
		)
		destination = visible_nest.global_position
	for unit in units:
		if visible_nest != null:
			unit.call("attack_target", visible_nest)
		else:
			unit.call("move_to", destination + _formation_offset(unit, units))
		unit.set_meta(&"human_ai_expedition", _expedition_count + 1)
	_exploration_cursor = (direction + 1) % 4
	_expedition_count += 1
	expedition_dispatched.emit(direction, units, visible_nest, destination)
	return true


func set_battle_elapsed(value: float) -> void:
	_battle_elapsed = maxf(value, 0.0)


func get_battle_elapsed() -> float:
	return _battle_elapsed


func get_last_threat_scores() -> Dictionary[int, float]:
	return _last_threat_scores.duplicate()


func get_analysis_count() -> int:
	return _analysis_count


func get_expedition_count() -> int:
	return _expedition_count


func get_direction_name(direction: DefenseDirection) -> String:
	return DIRECTION_NAMES[direction]


func _run_due_cycles(
	elapsed_property: StringName, interval: float, action: Callable
) -> void:
	var elapsed := float(get(elapsed_property))
	var cycles := 0
	while elapsed >= interval and cycles < config.maximum_catch_up_cycles:
		elapsed -= interval
		action.call()
		cycles += 1
	if cycles == config.maximum_catch_up_cycles:
		elapsed = fmod(elapsed, interval)
	set(elapsed_property, elapsed)


func _bind_dependencies() -> void:
	if human_economy == null or not is_instance_valid(human_economy):
		human_economy = get_tree().get_first_node_in_group(
			&"human_economy"
		) as HumanEconomy
	if placement_manager == null or not is_instance_valid(placement_manager):
		placement_manager = get_tree().get_first_node_in_group(
			&"building_placement_manager"
		) as BuildingPlacementManager
	if squad_manager == null or not is_instance_valid(squad_manager):
		squad_manager = get_tree().get_first_node_in_group(
			&"human_squad_manager"
		) as HumanSquadManager
	if fog_manager == null or not is_instance_valid(fog_manager):
		fog_manager = get_tree().get_first_node_in_group(
			&"human_fog_manager"
		) as FogOfWarManager
	if mvp_map == null or not is_instance_valid(mvp_map):
		mvp_map = get_tree().get_first_node_in_group(&"mvp_map")


func _get_build_direction(
	scores: Dictionary[int, float]
) -> DefenseDirection:
	var threatened := _get_strongest_threat_direction(scores)
	if float(scores[threatened]) >= config.threat_response_threshold:
		return threatened
	var counts: Dictionary[int, int] = {}
	for direction in DefenseDirection.values():
		counts[direction] = 0
	var human_base := _get_human_base()
	if human_base == null:
		return DefenseDirection.NORTH
	for tower in _get_living_towers():
		var direction := _classify_direction(
			tower.global_position - human_base.global_position
		)
		counts[direction] += 1
	var chosen := _balanced_direction_cursor
	for offset in 4:
		var candidate := (_balanced_direction_cursor + offset) % 4
		if counts[candidate] < counts[chosen]:
			chosen = candidate
	_balanced_direction_cursor = (chosen + 1) % 4
	return chosen as DefenseDirection


func _get_strongest_threat_direction(
	scores: Dictionary[int, float]
) -> DefenseDirection:
	var chosen := DefenseDirection.NORTH
	for direction in DefenseDirection.values():
		if float(scores.get(direction, 0.0)) > float(scores.get(chosen, 0.0)):
			chosen = direction
	return chosen


func _respond_to_threat(direction: DefenseDirection) -> bool:
	var monsters := _get_visible_monsters()
	var human_base := _get_human_base()
	if monsters.is_empty() or human_base == null:
		return false
	var target := monsters[0]
	var best_distance := target.global_position.distance_squared_to(
		human_base.global_position
	)
	for monster in monsters:
		if _classify_direction(
			monster.global_position - human_base.global_position
		) != direction:
			continue
		var distance := monster.global_position.distance_squared_to(
			human_base.global_position
		)
		if distance < best_distance:
			target = monster
			best_distance = distance
	var units := _get_ai_members()
	if units.is_empty():
		return false
	for unit in units:
		unit.call("attack_target", target)
		unit.set_meta(&"human_ai_defense_direction", direction)
	defense_response_ordered.emit(direction, units, target)
	return true


func _get_build_candidates(direction: DefenseDirection) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var human_base := _get_human_base()
	if human_base == null:
		return result
	var forward: Vector2 = DIRECTION_VECTORS[direction]
	var lateral := Vector2(-forward.y, forward.x)
	for radius in [config.inner_tower_radius, config.outer_tower_radius]:
		for lateral_offset in LATERAL_OFFSETS:
			result.append(
				human_base.global_position
				+ forward * float(radius)
				+ lateral * lateral_offset
			)
	return result


func _find_affordable_tower_index() -> int:
	var catalog := placement_manager.get_tower_data_catalog()
	for offset in config.tower_rotation.size():
		var rotation_index := (_tower_cursor + offset) % config.tower_rotation.size()
		var catalog_index := config.tower_rotation[rotation_index]
		if catalog_index < 0 or catalog_index >= catalog.size():
			continue
		var data := catalog[catalog_index]
		var cost := int(data.get("cost"))
		if human_economy.can_afford(cost + config.gold_reserve):
			_tower_cursor = rotation_index
			return catalog_index
	return -1


func _find_affordable_squad_index() -> int:
	var catalog := squad_manager.get_squad_catalog()
	for offset in config.squad_rotation.size():
		var rotation_index := (_squad_cursor + offset) % config.squad_rotation.size()
		var catalog_index := config.squad_rotation[rotation_index]
		if catalog_index < 0 or catalog_index >= catalog.size():
			continue
		var data := catalog[catalog_index] as HumanSquadData
		if data != null and human_economy.can_afford(
			data.cost + config.gold_reserve
		):
			_squad_cursor = rotation_index
			return catalog_index
	return -1


func _get_visible_monsters() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for actor_node in get_tree().get_nodes_in_group(&"combat_units"):
		var actor := actor_node as Node2D
		if not _is_living_monster(actor):
			continue
		if fog_manager != null and not fog_manager.is_node_visible_to_human(actor):
			continue
		result.append(actor)
	return result


func _get_monster_threat(monster: Node2D) -> float:
	var score := 8.0
	var health := monster.get_node_or_null("HealthComponent") as HealthComponent
	if health != null:
		score += health.current_health * 0.025
	if monster.has_method("get_monster_data"):
		var data := monster.call("get_monster_data") as MonsterProductionData
		if data != null:
			score += data.damage / maxf(data.attack_interval, 0.05) * 0.25
	return score


func _get_living_towers() -> Array[Node2D]:
	var result: Array[Node2D] = []
	if placement_manager == null:
		return result
	for tower in placement_manager.get_placed_buildings():
		var health := tower.get_node_or_null("HealthComponent") as HealthComponent
		if health == null or not health.is_dead:
			result.append(tower)
	return result


func _get_ai_squads() -> Array[Node2D]:
	var result: Array[Node2D] = []
	if squad_manager == null:
		return result
	for squad in squad_manager.get_recruited_squads():
		if not squad.get_meta(&"human_ai_controlled", false):
			continue
		for child in squad.get_children():
			var member := child as Node2D
			if member == null:
				continue
			var health := member.get_node_or_null(
				"HealthComponent"
			) as HealthComponent
			if health == null or not health.is_dead:
				result.append(squad)
				break
	return result


func _get_ai_members() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for member_node in get_tree().get_nodes_in_group(&"human_squad_members"):
		var member := member_node as Node2D
		if (
			member == null
			or not member.get_meta(&"human_ai_controlled", false)
		):
			continue
		var health := member.get_node_or_null("HealthComponent") as HealthComponent
		if health == null or not health.is_dead:
			result.append(member)
	return result


func _find_nearest_visible_nest(from_position: Vector2) -> Node2D:
	if mvp_map == null:
		return null
	var nearest: Node2D
	var nearest_distance := INF
	for nest in mvp_map.call("get_active_nests"):
		if (
			not nest is Node2D
			or fog_manager != null
			and not fog_manager.is_node_visible_to_human(nest)
		):
			continue
		var distance := (nest as Node2D).global_position.distance_squared_to(
			from_position
		)
		if distance < nearest_distance:
			nearest = nest as Node2D
			nearest_distance = distance
	return nearest


func _get_exploration_point(direction: DefenseDirection) -> Vector2:
	var human_base := _get_human_base()
	if human_base == null:
		return Vector2.ZERO
	var result: Vector2 = human_base.global_position + (
		DIRECTION_VECTORS[direction] * config.exploration_radius
	)
	result.x = clampf(result.x, 100.0, 1180.0)
	result.y = clampf(result.y, 110.0, 650.0)
	return result


func _formation_offset(unit: Node2D, units: Array[Node2D]) -> Vector2:
	var index := units.find(unit)
	var columns := maxi(ceili(sqrt(float(units.size()))), 1)
	return Vector2(
		float(index % columns) - float(columns - 1) * 0.5,
		float(index / columns)
	) * 34.0


func _get_human_base() -> Node2D:
	if mvp_map == null:
		return null
	var human_base := mvp_map.get("human_base") as Node2D
	if human_base == null or not is_instance_valid(human_base):
		return null
	var health := human_base.get_node_or_null("HealthComponent") as HealthComponent
	return null if health != null and health.is_dead else human_base


func _is_living_monster(actor: Node2D) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	var faction := FactionComponent.find_on(actor)
	var health := actor.get_node_or_null("HealthComponent") as HealthComponent
	return (
		faction != null
		and faction.faction == FactionComponent.Faction.MONSTER
		and (health == null or not health.is_dead)
	)


func _classify_direction(offset: Vector2) -> DefenseDirection:
	if absf(offset.x) > absf(offset.y):
		return DefenseDirection.EAST if offset.x >= 0.0 else DefenseDirection.WEST
	return DefenseDirection.SOUTH if offset.y >= 0.0 else DefenseDirection.NORTH
