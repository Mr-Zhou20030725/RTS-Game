extends SceneTree

const MAP_SCENE := preload("res://scenes/map/mvp_map.tscn")
const MONSTER_ECONOMY_SCENE := preload(
	"res://scenes/economy/monster_economy.tscn"
)
const PRODUCTION_MANAGER_SCENE := preload(
	"res://scenes/units/monster_production_manager.tscn"
)
const BATTLE_SCENE := preload("res://scenes/battle/battle.tscn")


func _init() -> void:
	_run_validation()


func _run_validation() -> void:
	if not await _validate_all_nests_and_safe_spawns():
		return
	if not await _validate_battle_panel_and_fog_boundary():
		return
	print(
		"T18 validation passed: all four nests can be selected independently, "
		+ "costs are exact, monsters spawn beside the chosen nest without "
		+ "overlapping blockers, and hidden nests do not accept map clicks."
	)
	quit()


func _validate_all_nests_and_safe_spawns() -> bool:
	var map := MAP_SCENE.instantiate()
	map.generation_seed = 18
	var economy := MONSTER_ECONOMY_SCENE.instantiate() as MonsterEconomy
	economy.starting_dark_energy = 300
	economy.energy_per_nest = 0
	var manager := (
		PRODUCTION_MANAGER_SCENE.instantiate() as MonsterProductionManager
	)
	root.add_child(map)
	root.add_child(economy)
	root.add_child(manager)
	await process_frame
	await process_frame
	economy.set_process(false)

	var catalog := manager.get_production_catalog()
	if catalog.size() < 2:
		_fail("The T18 production catalog must expose selectable monster types.")
		return false
	var expected_energy := economy.get_dark_energy()
	var nests: Array[Node2D] = map.get_active_nests()
	if nests.size() != 4:
		_fail("The map did not expose all four active nests to production.")
		return false

	for index in nests.size():
		var nest := nests[index]
		var data := catalog[index % catalog.size()] as MonsterProductionData
		if not manager.select_nest(nest) or not manager.produce(
			index % catalog.size()
		):
			_fail("An active nest could not produce its selected monster type.")
			return false
		expected_energy -= data.cost
		var produced := manager.get_spawned_monsters()
		var monster := produced[produced.size() - 1]
		monster.set_physics_process(false)
		var distance := monster.global_position.distance_to(nest.global_position)
		if distance < 90.0 or distance > 170.0:
			_fail("A monster did not spawn in a reasonable area beside its nest.")
			return false
		if int(monster.get_meta(&"production_nest_id", 0)) != nest.get_instance_id():
			_fail("A produced monster was not attributed to the selected nest.")
			return false
		if not _is_clear_of_all_buildings(
			monster.global_position,
			data.collision_radius,
			manager.spawn_clearance
		):
			_fail("A produced monster overlapped a nest or building obstacle.")
			return false

	if economy.get_dark_energy() != expected_energy:
		_fail("Monster production did not deduct the exact catalog costs.")
		return false
	if manager.get_spawned_monsters().size() != 4:
		_fail("The four independently selected nests did not create four monsters.")
		return false

	_cleanup([map, economy, manager])
	await process_frame
	return true


func _validate_battle_panel_and_fog_boundary() -> bool:
	var battle := BATTLE_SCENE.instantiate()
	root.add_child(battle)
	await process_frame
	await process_frame
	var manager := battle.get_node(
		"MonsterProductionManager"
	) as MonsterProductionManager
	var map := battle.get_node("MVPMap")
	var fog := battle.get_node("FogOfWarManager") as FogOfWarManager
	var hud := battle.get_node("HUDLayer/BattleHUD") as Control
	var panel := hud.get_node("MonsterProductionPanel") as ColorRect
	var first_button := panel.get_node("MonsterTypeZeroButton") as Button
	var second_button := panel.get_node("MonsterTypeOneButton") as Button
	if manager == null or panel == null or panel.visible:
		_fail("The battle production panel was not initialized hidden.")
		return false

	var hidden_nest: Node2D
	for candidate in map.get_active_nests():
		if not candidate.visible:
			hidden_nest = candidate
			break
	if hidden_nest != null and manager.select_nest_at(
		hidden_nest.global_position, true
	):
		_fail("A fog-hidden nest accepted a normal map click.")
		return false

	fog.set_human_fog_enabled(false)
	var visible_nest := map.get_active_nests()[0] as Node2D
	if not manager.select_nest_at(visible_nest.global_position, true):
		_fail("A visible nest did not accept a map-position selection.")
		return false
	if not panel.visible or first_button.disabled or second_button.disabled:
		_fail("Selecting a nest did not expose enabled production choices.")
		return false
	var first_cost := manager.get_effective_cost(0)
	var second_cost := manager.get_effective_cost(1)
	if (
		str(first_cost) + " DARK" not in first_button.text
		or str(second_cost) + " DARK" not in second_button.text
	):
		_fail("The production panel did not display both monster costs.")
		return false
	var before_count := manager.get_spawned_monsters().size()
	var before_energy: int = int(
		battle.get_node("MonsterEconomy").call("get_dark_energy")
	)
	first_button.pressed.emit()
	if (
		manager.get_spawned_monsters().size() != before_count + 1
		or int(battle.get_node("MonsterEconomy").call("get_dark_energy"))
		!= before_energy - first_cost
	):
		_fail("The production UI did not create and charge for its monster.")
		return false

	_cleanup([battle])
	await process_frame
	return true


func _is_clear_of_all_buildings(
	position: Vector2, unit_radius: float, clearance: float
) -> bool:
	for blocker in get_nodes_in_group(&"placement_blockers"):
		if not blocker is Node2D:
			continue
		var footprint := blocker.get_node_or_null("BuildingFootprint")
		if footprint == null:
			continue
		var minimum_distance := (
			float(footprint.get("radius")) + unit_radius + clearance
		)
		if blocker.global_position.distance_to(position) < minimum_distance:
			return false
	return true


func _cleanup(nodes: Array) -> void:
	for node in nodes:
		if node != null and is_instance_valid(node):
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.queue_free()


func _fail(message: String) -> void:
	push_error("T18 validation failed: %s" % message)
	quit(1)
