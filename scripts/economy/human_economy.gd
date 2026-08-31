class_name HumanEconomy
extends Node

## Owns Human gold income, rewards, and validated spending.

signal gold_changed(current_gold: int, change: int, reason: StringName)
signal spend_rejected(cost: int, current_gold: int)
signal kill_reward_granted(victim: Node, amount: int)

@export_range(0, 1000000, 1) var starting_gold := 100
@export_range(0, 1000000, 1) var passive_income_amount := 5
@export_range(0.1, 3600.0, 0.1) var passive_income_interval := 2.0
@export_range(0, 1000000, 1) var monster_kill_reward := 25

var current_gold := 0
var _income_elapsed := 0.0
var _tracked_health_ids: Dictionary[int, bool] = {}


func _ready() -> void:
	current_gold = maxi(starting_gold, 0)
	get_tree().node_added.connect(_on_tree_node_added)
	call_deferred("_scan_existing_monster_units")
	gold_changed.emit(current_gold, current_gold, &"starting_gold")


func _process(delta: float) -> void:
	if passive_income_amount <= 0 or passive_income_interval <= 0.0:
		return

	_income_elapsed += delta
	if _income_elapsed < passive_income_interval:
		return

	var completed_intervals := floori(
		_income_elapsed / passive_income_interval
	)
	_income_elapsed -= completed_intervals * passive_income_interval
	add_gold(
		passive_income_amount * completed_intervals,
		&"passive_income"
	)


func get_gold() -> int:
	return current_gold


func can_afford(cost: int) -> bool:
	return cost >= 0 and current_gold >= cost


func try_spend(cost: int, reason: StringName = &"purchase") -> bool:
	if cost < 0 or not can_afford(cost):
		spend_rejected.emit(cost, current_gold)
		return false
	if cost == 0:
		return true

	current_gold -= cost
	gold_changed.emit(current_gold, -cost, reason)
	return true


func add_gold(amount: int, reason: StringName = &"reward") -> int:
	if amount <= 0:
		return 0

	current_gold += amount
	gold_changed.emit(current_gold, amount, reason)
	return amount


func _scan_existing_monster_units() -> void:
	for actor in get_tree().get_nodes_in_group(&"combat_units"):
		_try_track_monster_unit(actor)


func _on_tree_node_added(node: Node) -> void:
	_try_track_monster_unit(node)


func _try_track_monster_unit(actor: Node) -> void:
	if actor == null or not actor.is_in_group(&"combat_units"):
		return
	var faction := FactionComponent.find_on(actor)
	if faction == null or faction.faction != FactionComponent.Faction.MONSTER:
		return

	var health := actor.get_node_or_null("HealthComponent") as HealthComponent
	if health == null or _tracked_health_ids.has(health.get_instance_id()):
		return

	_tracked_health_ids[health.get_instance_id()] = true
	health.died.connect(_on_monster_unit_died.bind(actor), CONNECT_ONE_SHOT)


func _on_monster_unit_died(source: Node, victim: Node) -> void:
	var source_faction := FactionComponent.find_on(source)
	if (
		source_faction == null
		or source_faction.faction != FactionComponent.Faction.HUMAN
	):
		return
	if monster_kill_reward <= 0:
		return

	add_gold(monster_kill_reward, &"monster_kill")
	kill_reward_granted.emit(victim, monster_kill_reward)
