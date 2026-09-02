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
	var economy := battle.get_node("HumanEconomy") as HumanEconomy
	var placement := battle.get_node(
		"BuildingPlacementManager"
	) as BuildingPlacementManager
	var squads := battle.get_node("HumanSquadManager") as HumanSquadManager
	var ai := battle.get_node("HumanAIController") as HumanAIController
	var monster_ai := battle.get_node(
		"MonsterAIController"
	) as MonsterAIController
	var fog := battle.get_node("FogOfWarManager") as FogOfWarManager
	var hud := battle.get_node("HUDLayer/BattleHUD") as Control
	if ai == null or ai.config == null or not ai.is_ai_enabled():
		_fail("Human AI v1 is missing, unconfigured, or disabled by default.")
		return
	ai.set_process(false)
	monster_ai.set_ai_enabled(false)
	economy.set_process(false)
	economy.add_gold(2500, &"t25_validation")
	var human_base := map.get("human_base") as Node2D
	var threat := _prepare_single_visible_threat(human_base)
	if threat == null:
		_fail("Could not prepare a visible Monster threat.")
		return
	fog.refresh_visibility()
	var north_scores := ai.analyze_visible_threats()
	if (
		float(north_scores[HumanAIController.DefenseDirection.NORTH])
		<= float(north_scores[HumanAIController.DefenseDirection.EAST])
	):
		_fail("Visible northern pressure was not classified as a northern threat.")
		return

	if not ai.run_build_cycle():
		_fail("Human AI did not build in response to visible pressure.")
		return
	var towers := placement.get_placed_buildings()
	if (
		towers.size() != 1
		or towers[0].get_meta(&"human_ai_defense_direction", -1)
		!= HumanAIController.DefenseDirection.NORTH
	):
		_fail("The first AI tower did not reinforce the threatened northern side.")
		return

	threat.global_position = human_base.global_position + Vector2(190.0, 0.0)
	fog.refresh_visibility()
	if not ai.run_build_cycle():
		_fail("Human AI did not reinforce a changed threat direction.")
		return
	towers = placement.get_placed_buildings()
	if (
		towers.size() != 2
		or towers[1].get_meta(&"human_ai_defense_direction", -1)
		!= HumanAIController.DefenseDirection.EAST
		or towers[0].global_position == towers[1].global_position
	):
		_fail("AI tower spending remained concentrated at one meaningless spot.")
		return

	threat.global_position = human_base.global_position + Vector2(0.0, 190.0)
	fog.refresh_visibility()
	if not ai.run_build_cycle() or placement.get_placed_buildings().size() < 3:
		_fail("Human AI could not reinforce a third active threat direction.")
		return
	if _unique_tower_positions(placement).size() < 3:
		_fail("AI reused an occupied tower position instead of spreading defense.")
		return

	if not ai.run_recruit_cycle() or not ai.run_recruit_cycle():
		_fail("Human AI did not recruit multiple squads.")
		return
	var ai_squads := _get_ai_squads(squads)
	if ai_squads.size() != 2:
		_fail("Recruited squads were not marked as Human-AI controlled.")
		return
	var recruited_types: Dictionary[StringName, bool] = {}
	for squad in ai_squads:
		for child in squad.get_children():
			var member := child as HumanSquadMember
			if member == null or not member.get_meta(&"human_ai_controlled", false):
				_fail("A recruited squad member was not assigned to Human AI.")
				return
			recruited_types[member.get_squad_data().squad_id] = true
	if recruited_types.size() < 2:
		_fail("Human AI recruitment did not rotate squad roles.")
		return

	threat.global_position = human_base.global_position + Vector2(190.0, 0.0)
	fog.refresh_visibility()
	if not ai.run_analysis_cycle():
		_fail("Human AI did not issue a response to an active attack.")
		return
	for member in _get_ai_members():
		if member.call("get_command_target") != threat:
			_fail("An AI squad member did not respond to the visible attacker.")
			return

	threat.global_position = Vector2(90.0, 640.0)
	var active_nests: Array[Node2D] = map.call("get_active_nests")
	var hidden_test_positions := [
		Vector2(100.0, 110.0),
		Vector2(1180.0, 110.0),
		Vector2(1180.0, 650.0),
		Vector2(100.0, 650.0),
	]
	for index in active_nests.size():
		active_nests[index].global_position = hidden_test_positions[index]
	_center_human_units(human_base)
	fog.refresh_visibility()
	ai.set_battle_elapsed(ai.config.midgame_start_time + 1.0)
	if not ai.run_expedition_cycle():
		_fail("Stable mid-game defense did not dispatch a scouting expedition.")
		return
	var expedition_had_visible_target := false
	for member in _get_ai_members():
		var commanded_target := member.call("get_command_target") as Node2D
		if commanded_target in active_nests:
			if not fog.is_node_visible_to_human(commanded_target):
				_fail("Human AI targeted a hidden nest through fog of war.")
				return
			expedition_had_visible_target = true
		elif not member.call("has_move_target"):
			_fail("A scouting squad member did not receive an exploration order.")
			return
	if expedition_had_visible_target:
		_fail("Hidden-nest setup failed to exercise the search behavior.")
		return

	var visible_nest := _find_visible_nest(active_nests, fog)
	if visible_nest == null:
		visible_nest = active_nests[0]
		var scout := _get_ai_members()[0]
		scout.global_position = visible_nest.global_position + Vector2(70.0, 0.0)
		fog.refresh_visibility()
	if not fog.is_node_visible_to_human(visible_nest):
		_fail("Test expedition could not reveal its nearby nest.")
		return
	if not ai.run_expedition_cycle():
		_fail("Human AI did not counterattack after discovering a nest.")
		return
	var counterattack_target: Node2D
	for member in _get_ai_members():
		var commanded_nest := member.call("get_command_target") as Node2D
		if (
			commanded_nest not in active_nests
			or not fog.is_node_visible_to_human(commanded_nest)
		):
			_fail("Counterattack did not explicitly target the visible nest.")
			return
		if counterattack_target == null:
			counterattack_target = commanded_nest
		elif commanded_nest != counterattack_target:
			_fail("Counterattack squad split across unrelated nest targets.")
			return

	var human_ai_button := hud.get_node(
		"SquadRecruitBar/HumanAIButton"
	) as Button
	if human_ai_button == null or "ON" not in human_ai_button.text:
		_fail("Human HUD does not expose the AI pause control.")
		return
	human_ai_button.pressed.emit()
	if ai.is_ai_enabled() or "PAUSED" not in human_ai_button.text:
		_fail("Human AI could not be paused for manual control.")
		return
	human_ai_button.pressed.emit()
	if not ai.is_ai_enabled():
		_fail("Human AI could not resume after a manual pause.")
		return
	var analysis_before := ai.get_analysis_count()
	var expeditions_before := ai.get_expedition_count()
	for _second in 600:
		economy._process(1.0)
		ai.advance_simulation(1.0)
	if (
		ai.get_analysis_count() - analysis_before < 250
		or ai.get_expedition_count() <= expeditions_before
	):
		_fail("Ten simulated minutes did not keep Human AI decisions active.")
		return

	print(
		"T25 validation passed: Human AI reads only visible four-way threats, "
		+ "spreads tower spending, rotates squads, responds to attacks, scouts "
		+ "without fog leaks, counterattacks discovered nests, and remains "
		+ "active through 10 simulated minutes (visible at first dispatch: "
		+ "%s)." % expedition_had_visible_target
	)
	quit()


func _prepare_single_visible_threat(human_base: Node2D) -> Node2D:
	var chosen: Node2D
	for candidate in get_nodes_in_group(&"combat_units"):
		var actor := candidate as Node2D
		var faction := FactionComponent.find_on(actor)
		if faction == null or faction.faction != FactionComponent.Faction.MONSTER:
			continue
		actor.call("stop_moving")
		actor.global_position = Vector2(90.0, 640.0)
		if chosen == null:
			chosen = actor
	if chosen != null:
		chosen.global_position = human_base.global_position + Vector2(0.0, -190.0)
	return chosen


func _unique_tower_positions(
	placement: BuildingPlacementManager
) -> Dictionary[Vector2, bool]:
	var positions: Dictionary[Vector2, bool] = {}
	for tower in placement.get_placed_buildings():
		positions[tower.global_position] = true
	return positions


func _get_ai_squads(manager: HumanSquadManager) -> Array[Node2D]:
	var result: Array[Node2D] = []
	for squad in manager.get_recruited_squads():
		if squad.get_meta(&"human_ai_controlled", false):
			result.append(squad)
	return result


func _get_ai_members() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for candidate in get_nodes_in_group(&"human_squad_members"):
		var member := candidate as Node2D
		if member != null and member.get_meta(&"human_ai_controlled", false):
			result.append(member)
	return result


func _find_visible_nest(
	nests: Array[Node2D], fog: FogOfWarManager
) -> Node2D:
	for nest in nests:
		if fog.is_node_visible_to_human(nest):
			return nest
	return null


func _center_human_units(human_base: Node2D) -> void:
	var index := 0
	for candidate in get_nodes_in_group(&"combat_units"):
		var unit := candidate as Node2D
		var faction := FactionComponent.find_on(unit)
		if faction == null or faction.faction != FactionComponent.Faction.HUMAN:
			continue
		unit.call("stop_moving")
		unit.global_position = human_base.global_position + Vector2(
			float(index % 4) * 8.0, float(index / 4) * 8.0
		)
		index += 1


func _fail(message: String) -> void:
	push_error("T25 validation failed: %s" % message)
	quit(1)
