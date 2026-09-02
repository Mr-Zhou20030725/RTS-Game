extends SceneTree

const BATTLE_SCENE := preload("res://scenes/battle/battle.tscn")


func _init() -> void:
	_run_validation()


func _run_validation() -> void:
	var battle := BATTLE_SCENE.instantiate()
	root.add_child(battle)
	await process_frame
	await physics_frame
	await physics_frame
	var fog := battle.get_node("FogOfWarManager") as FogOfWarManager
	var map := battle.get_node("MVPMap")
	var economy := battle.get_node("MonsterEconomy") as MonsterEconomy
	var production := battle.get_node(
		"MonsterProductionManager"
	) as MonsterProductionManager
	var selection := battle.get_node(
		"SelectionManager"
	) as UnitSelectionManager
	var legions := battle.get_node(
		"MonsterLegionManager"
	) as MonsterLegionManager
	economy.set_process(false)
	economy.add_dark_energy(500, &"t23_validation")
	production.select_nest(map.call("get_active_nests")[0] as Node2D)
	for catalog_index in [0, 3]:
		if not production.produce(catalog_index):
			_fail("Could not produce the mixed legion used by T23.")
			return
	var units := production.get_spawned_monsters()
	fog.set_viewer_faction(FogOfWarManager.ViewerFaction.MONSTER)
	await process_frame
	selection.select_units(units)
	if not legions.create_legion(1) or not legions.select_legion(1):
		_fail("Could not prepare a selected Monster legion for routing.")
		return

	var waypoints := [
		Vector2(250.0, 180.0),
		Vector2(250.0, 540.0),
		Vector2(540.0, 620.0),
	]
	for waypoint in waypoints:
		selection.issue_context_command(waypoint, true)
	var human_base := map.get("human_base") as Node2D
	selection.issue_context_command(human_base.global_position, true)
	for unit in units:
		var route: Array = unit.call("get_waypoint_route")
		if (
			route.size() != 3
			or unit.call("get_route_attack_target") != human_base
			or not _is_clear_detour(route)
		):
			_fail("Shift commands did not create three ordered detour points and a final attack.")
			return

	for unit in units:
		for remaining_count in [2, 1, 0]:
			unit.global_position = unit.call("get_move_target")
			unit.call("_physics_process", 0.016)
			if (unit.call("get_waypoint_route") as Array).size() != remaining_count:
				_fail("A legion member did not advance through waypoints in order.")
				return
		if unit.call("get_command_target") != human_base:
			_fail("The legion did not attack its target after the final waypoint.")
			return

	for waypoint in waypoints:
		selection.issue_context_command(waypoint, true)
	selection.issue_context_command(human_base.global_position, true)
	var replacement := Vector2(940.0, 300.0)
	selection.issue_context_command(replacement, false)
	for unit in units:
		if (
			not (unit.call("get_waypoint_route") as Array).is_empty()
			or unit.call("get_route_attack_target") != null
			or unit.call("get_command_target") != null
			or not unit.call("is_manual_move_order_active")
			or unit.call("get_move_target").distance_to(replacement) > 80.0
		):
			_fail("A new normal command did not completely replace the old route.")
			return

	print(
		"T23 validation passed: a selected mixed legion follows three visible "
		+ "detour waypoints before attacking, and a new command replaces the "
		+ "route immediately."
	)
	quit()


func _is_clear_detour(route: Array) -> bool:
	if route.size() != 3:
		return false
	var first := route[0] as Vector2
	var second := route[1] as Vector2
	var third := route[2] as Vector2
	return (
		absf(second.y - first.y) > 250.0
		and absf(third.x - second.x) > 200.0
	)


func _fail(message: String) -> void:
	push_error("T23 validation failed: %s" % message)
	quit(1)
