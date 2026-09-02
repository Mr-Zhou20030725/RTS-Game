class_name MonsterEconomy
extends Node

## Owns Monster dark energy income, kill rewards, and validated spending.

signal dark_energy_changed(
	current_energy: int, change: int, reason: StringName
)
signal spend_rejected(cost: int, current_energy: int)
signal income_rate_changed(active_nests: int, energy_per_interval: int)
signal kill_reward_granted(victim: Node, amount: int)

@export_range(0, 1000000, 1) var starting_dark_energy := 40
@export_range(0, 1000000, 1) var energy_per_nest := 2
@export_range(0.1, 3600.0, 0.1) var income_interval := 2.0
@export_range(0, 1000000, 1) var human_unit_kill_reward := 10
@export_range(0, 1000000, 1) var human_tower_kill_reward := 15

var current_dark_energy := 0
var _active_nest_count := 0
var _income_elapsed := 0.0
var _nest_income_multiplier := 1.0
var _tracked_health_ids: Dictionary[int, bool] = {}
var _mvp_map: Node


func _ready() -> void:
	current_dark_energy = maxi(starting_dark_energy, 0)
	get_tree().node_added.connect(_on_tree_node_added)
	call_deferred("_bind_map_and_scan_human_targets")
	dark_energy_changed.emit(
		current_dark_energy, current_dark_energy, &"starting_dark_energy"
	)


func _process(delta: float) -> void:
	var income_per_interval := get_income_per_interval()
	if income_per_interval <= 0 or income_interval <= 0.0:
		return
	_income_elapsed += delta
	if _income_elapsed < income_interval:
		return
	var completed_intervals := floori(_income_elapsed / income_interval)
	_income_elapsed -= completed_intervals * income_interval
	add_dark_energy(
		income_per_interval * completed_intervals, &"nest_income"
	)


func get_dark_energy() -> int:
	return current_dark_energy


func get_active_nest_count() -> int:
	return _active_nest_count


func get_income_per_interval() -> int:
	return roundi(
		float(_active_nest_count)
		* float(energy_per_nest)
		* _nest_income_multiplier
	)


func get_nest_income_multiplier() -> float:
	return _nest_income_multiplier


func set_nest_income_multiplier(value: float) -> void:
	var next_multiplier := maxf(value, 0.0)
	if is_equal_approx(next_multiplier, _nest_income_multiplier):
		return
	_nest_income_multiplier = next_multiplier
	income_rate_changed.emit(_active_nest_count, get_income_per_interval())


func can_afford(cost: int) -> bool:
	return cost >= 0 and current_dark_energy >= cost


func try_spend(
	cost: int, reason: StringName = &"monster_production"
) -> bool:
	if cost < 0 or not can_afford(cost):
		spend_rejected.emit(cost, current_dark_energy)
		return false
	if cost == 0:
		return true
	current_dark_energy -= cost
	dark_energy_changed.emit(current_dark_energy, -cost, reason)
	return true


func add_dark_energy(
	amount: int, reason: StringName = &"reward"
) -> int:
	if amount <= 0:
		return 0
	current_dark_energy += amount
	dark_energy_changed.emit(current_dark_energy, amount, reason)
	return amount


func _bind_map_and_scan_human_targets() -> void:
	_mvp_map = get_tree().get_first_node_in_group(&"mvp_map")
	if _mvp_map != null:
		_set_active_nest_count(int(_mvp_map.call("get_active_nest_count")))
		_mvp_map.active_nest_count_changed.connect(
			_on_active_nest_count_changed
		)
	for actor in get_tree().get_nodes_in_group(&"combat_units"):
		_try_track_human_target(actor)
	for actor in get_tree().get_nodes_in_group(&"combat_buildings"):
		_try_track_human_target(actor)


func _on_active_nest_count_changed(current_count: int) -> void:
	_set_active_nest_count(current_count)


func _set_active_nest_count(value: int) -> void:
	var next_count := maxi(value, 0)
	if next_count == _active_nest_count:
		return
	_active_nest_count = next_count
	income_rate_changed.emit(_active_nest_count, get_income_per_interval())


func _on_tree_node_added(node: Node) -> void:
	_try_track_human_target(node)


func _try_track_human_target(actor: Node) -> void:
	if actor == null:
		return
	var is_unit := actor.is_in_group(&"combat_units")
	var is_tower := actor.has_method("get_tower_data")
	if not is_unit and not is_tower:
		return
	var faction := FactionComponent.find_on(actor)
	if faction == null or faction.faction != FactionComponent.Faction.HUMAN:
		return
	var health := actor.get_node_or_null("HealthComponent") as HealthComponent
	if health == null or _tracked_health_ids.has(health.get_instance_id()):
		return
	_tracked_health_ids[health.get_instance_id()] = true
	health.died.connect(
		_on_human_target_died.bind(actor, is_unit, is_tower),
		CONNECT_ONE_SHOT
	)


func _on_human_target_died(
	source: Node, victim: Node, is_unit: bool, is_tower: bool
) -> void:
	var source_faction := FactionComponent.find_on(source)
	if (
		source_faction == null
		or source_faction.faction != FactionComponent.Faction.MONSTER
	):
		return
	var reward := 0
	if is_unit:
		reward = human_unit_kill_reward
	elif is_tower:
		reward = human_tower_kill_reward
	if reward <= 0:
		return
	add_dark_energy(reward, &"human_kill")
	kill_reward_granted.emit(victim, reward)
