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
	var map := battle.get_node("MVPMap")
	var economy := battle.get_node("MonsterEconomy") as MonsterEconomy
	var production := battle.get_node(
		"MonsterProductionManager"
	) as MonsterProductionManager
	var ai := battle.get_node("MonsterAIController") as MonsterAIController
	var fog := battle.get_node("FogOfWarManager") as FogOfWarManager
	var hud := battle.get_node("HUDLayer/BattleHUD") as Control
	if ai == null or ai.config == null or not ai.is_ai_enabled():
		_fail("Monster AI v1 is missing, unconfigured, or disabled by default.")
		return
	ai.set_process(false)
	economy.set_process(false)
	_arrange_human_defenses(map)
	var scores := ai.analyze_defense_strengths()
	if not _validate_direction_analysis(scores):
		return

	economy.add_dark_energy(2000, &"t24_validation")
	var initial_count := production.get_spawned_monsters().size()
	for _cycle in 6:
		ai.run_production_cycle()
	var ai_monsters := _get_ai_monsters(production)
	if ai_monsters.size() < 4 or ai_monsters.size() <= initial_count:
		_fail("Monster AI did not continuously produce a usable basic wave.")
		return
	var produced_types: Dictionary[StringName, bool] = {}
	for monster in ai_monsters:
		produced_types[monster.get_meta(&"monster_type_id", &"")] = true
	if produced_types.size() < 2:
		_fail("Monster AI production did not rotate through basic unit types.")
		return

	if not ai.launch_attack_wave():
		_fail("Monster AI did not launch its first available wave.")
		return
	var history := ai.get_direction_history()
	if history.is_empty():
		_fail("Monster AI did not record its chosen attack direction.")
		return
	var weakest_direction := _find_weakest_direction(scores)
	if history[0] != weakest_direction:
		_fail("The first Monster wave did not choose the weakest Human sector.")
		return
	var human_base := map.get("human_base") as Node2D
	var assigned_count := 0
	for monster in ai_monsters:
		if not monster.get_meta(&"ai_wave_assigned", false):
			continue
		assigned_count += 1
		if (
			monster.call("get_route_attack_target") != human_base
			or (monster.call("get_waypoint_route") as Array).is_empty()
		):
			_fail("An AI wave did not stage through its chosen side and attack the base.")
			return
	if assigned_count < ai.config.minimum_wave_size:
		_fail("The launched Monster wave was smaller than its configured minimum.")
		return

	for _wave_index in 3:
		for _production_index in ai.config.minimum_wave_size:
			ai.run_production_cycle()
		ai.launch_attack_wave()
	var unique_directions: Dictionary[int, bool] = {}
	for direction in ai.get_direction_history():
		unique_directions[direction] = true
	if unique_directions.size() < 2:
		_fail("Repeated Monster waves remained fixed to one direction.")
		return

	var attempts_before := ai.get_production_attempt_count()
	for _second in 600:
		economy._process(1.0)
		ai.advance_simulation(1.0)
	if (
		ai.get_production_attempt_count() - attempts_before < 160
		or ai.get_analysis_count() < 10
	):
		_fail("Ten simulated minutes did not keep AI production and analysis active.")
		return

	fog.set_viewer_faction(FogOfWarManager.ViewerFaction.MONSTER)
	await process_frame
	var ai_button := hud.get_node("MonsterCommandPanel/MonsterAIButton") as Button
	if ai_button == null or "ON" not in ai_button.text:
		_fail("Monster HUD does not expose the AI pause control.")
		return
	ai_button.pressed.emit()
	if ai.is_ai_enabled() or "PAUSED" not in ai_button.text:
		_fail("Monster AI could not be paused for manual legion control.")
		return
	ai_button.pressed.emit()
	if not ai.is_ai_enabled():
		_fail("Monster AI could not resume after a manual pause.")
		return

	print(
		"T24 validation passed: rule AI scores four Human defense sectors, "
		+ "rotates basic production, launches active waves toward weaker sides, "
		+ "varies directions, and remains active through 10 simulated minutes."
	)
	quit()


func _arrange_human_defenses(map: Node) -> void:
	var human_base := map.get("human_base") as Node2D
	var human_units: Array[Node2D] = []
	for candidate in get_nodes_in_group(&"combat_units"):
		var unit := candidate as Node2D
		var faction := FactionComponent.find_on(unit)
		if faction != null and faction.faction == FactionComponent.Faction.HUMAN:
			human_units.append(unit)
	var offsets := [
		Vector2(-80.0, -220.0),
		Vector2(0.0, -240.0),
		Vector2(80.0, -220.0),
		Vector2(240.0, -60.0),
		Vector2(230.0, 60.0),
		Vector2(-230.0, 0.0),
	]
	for index in mini(human_units.size(), offsets.size()):
		human_units[index].call("stop_moving")
		human_units[index].global_position = human_base.global_position + offsets[index]


func _validate_direction_analysis(scores: Dictionary) -> bool:
	for direction in MonsterAIController.AttackDirection.values():
		if not scores.has(direction):
			_fail("Defense analysis omitted one of the four map directions.")
			return false
	if (
		float(scores[MonsterAIController.AttackDirection.NORTH])
		<= float(scores[MonsterAIController.AttackDirection.SOUTH])
	):
		_fail("Human unit concentration did not increase its sector defense score.")
		return false
	return true


func _find_weakest_direction(scores: Dictionary) -> int:
	var weakest := MonsterAIController.AttackDirection.NORTH
	var weakest_score := INF
	for direction in MonsterAIController.AttackDirection.values():
		var score := float(scores[direction])
		if score < weakest_score:
			weakest = direction
			weakest_score = score
	return weakest


func _get_ai_monsters(
	production: MonsterProductionManager
) -> Array[Node2D]:
	var result: Array[Node2D] = []
	for monster in production.get_spawned_monsters():
		if monster.get_meta(&"ai_controlled", false):
			result.append(monster)
	return result


func _fail(message: String) -> void:
	push_error("T24 validation failed: %s" % message)
	quit(1)
