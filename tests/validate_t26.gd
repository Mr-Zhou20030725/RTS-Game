extends SceneTree

const MAIN_SCENE := "res://scenes/main/main.tscn"
const GAME_MANAGER_SCRIPT := preload("res://scripts/core/game_manager.gd")


func _init() -> void:
	if not root.has_node("GameManager"):
		var game_manager := GAME_MANAGER_SCRIPT.new()
		game_manager.name = "GameManager"
		root.add_child(game_manager)
	_run_validation()


func _run_validation() -> void:
	var game_manager := root.get_node_or_null("GameManager")
	if game_manager == null:
		_fail("GameManager autoload is unavailable.")
		return
	if change_scene_to_file(MAIN_SCENE) != OK:
		_fail("Main scene could not be loaded.")
		return
	await process_frame
	await process_frame
	var human_button := current_scene.find_child(
		"StartButton", true, false
	) as Button
	var monster_button := current_scene.find_child(
		"MonsterStartButton", true, false
	) as Button
	if human_button == null or monster_button == null:
		_fail("Main menu does not offer both faction choices.")
		return

	human_button.pressed.emit()
	await process_frame
	await process_frame
	await process_frame
	if not _validate_human_session(game_manager):
		return

	game_manager.call("return_to_main")
	await process_frame
	await process_frame
	monster_button = current_scene.find_child(
		"MonsterStartButton", true, false
	) as Button
	if monster_button == null:
		_fail("Monster choice disappeared after returning to Main.")
		return
	monster_button.pressed.emit()
	await process_frame
	await process_frame
	await process_frame
	if not _validate_monster_session(game_manager):
		return

	print(
		"T26 validation passed: both Main-menu faction choices create a locked "
		+ "player session, enable only the opposing AI, expose the correct "
		+ "commands and vision, and preserve Human/Monster combat identity."
	)
	quit()


func _validate_human_session(game_manager: Node) -> bool:
	var battle := current_scene
	if (
		battle == null
		or battle.name != "Battle"
		or int(game_manager.call("get_selected_player_faction"))
		!= GameManager.PlayerFaction.HUMAN
		or int(battle.call("get_player_faction"))
		!= GameManager.PlayerFaction.HUMAN
	):
		_fail("Human menu choice did not persist into Battle.")
		return false
	var fog := battle.get_node("FogOfWarManager") as FogOfWarManager
	var human_ai := battle.get_node("HumanAIController") as HumanAIController
	var monster_ai := battle.get_node(
		"MonsterAIController"
	) as MonsterAIController
	var selection := battle.get_node(
		"SelectionManager"
	) as UnitSelectionManager
	var hud := battle.get_node("HUDLayer/BattleHUD") as Control
	var world_camera := battle.get_node("WorldCamera") as WorldCamera
	if (
		fog.get_viewer_faction() != FogOfWarManager.ViewerFaction.HUMAN
		or human_ai.is_ai_enabled()
		or not monster_ai.is_ai_enabled()
		or selection.get_controlled_faction()
		!= FactionComponent.Faction.HUMAN
	):
		_fail("Human session vision, control, or opponent AI was inverted.")
		return false
	if (
		world_camera == null
		or not world_camera.enabled
		or world_camera.world_bounds.size != Vector2(4000.0, 4000.0)
	):
		_fail("The 4000 by 4000 battlefield camera is missing or misconfigured.")
		return false
	if not _validate_locked_hud(hud, true):
		return false
	var view_button := hud.get_node("TopBar/ViewModeButton") as Button
	view_button.pressed.emit()
	if fog.get_viewer_faction() != FogOfWarManager.ViewerFaction.HUMAN:
		_fail("Locked Human player could switch to Monster global vision.")
		return false

	if (
		_count_living_units(FactionComponent.Faction.HUMAN) != 3
		or _count_living_units(FactionComponent.Faction.MONSTER) != 0
	):
		_fail("Battle must start with exactly three Humans and no test Monsters.")
		return false
	var human_unit := _find_living_unit(FactionComponent.Faction.HUMAN)
	var monster_unit := _produce_test_monster(battle)
	if human_unit == null or monster_unit == null:
		_fail("Human session could not prepare units for control validation.")
		return false
	selection.select_single(human_unit)
	if selection.get_selected_units().is_empty():
		_fail("Human player could not select a Human unit.")
		return false
	selection.select_single(monster_unit)
	if not selection.get_selected_units().is_empty():
		_fail("Human player was allowed to control a Monster unit.")
		return false
	var destination := human_unit.global_position + Vector2(80.0, 0.0)
	selection.select_single(human_unit)
	selection.issue_move_command(destination)
	if not human_unit.call("has_move_target"):
		_fail("Human player could not issue a movement command.")
		return false

	var economy := battle.get_node("HumanEconomy") as HumanEconomy
	var placement := battle.get_node(
		"BuildingPlacementManager"
	) as BuildingPlacementManager
	var squads := battle.get_node("HumanSquadManager") as HumanSquadManager
	economy.set_process(false)
	economy.add_gold(500, &"t26_human_validation")
	var base := battle.get_node("MVPMap").get("human_base") as Node2D
	if (
		not placement.begin_tower_placement(
			0, base.global_position + Vector2(176.0, 0.0)
		)
		or not placement.confirm_placement()
		or not squads.recruit_squad(0)
	):
		_fail("Human player could not use tower and squad commands.")
		return false
	var placed_towers := placement.get_placed_buildings()
	var recruited_squads := squads.get_recruited_squads()
	if (
		base.scale != Vector2(0.975, 0.975)
		or human_unit.scale != Vector2(0.975, 0.975)
		or monster_unit.scale != Vector2(0.975, 0.975)
		or placed_towers[-1].scale != Vector2(0.975, 0.975)
		or recruited_squads[-1].get_child(0).scale != Vector2(0.975, 0.975)
	):
		_fail("World units and buildings do not share the reduced art scale.")
		return false
	return _validate_combat_identity(human_unit, monster_unit)


func _validate_monster_session(game_manager: Node) -> bool:
	var battle := current_scene
	if (
		battle == null
		or battle.name != "Battle"
		or int(game_manager.call("get_selected_player_faction"))
		!= GameManager.PlayerFaction.MONSTER
		or int(battle.call("get_player_faction"))
		!= GameManager.PlayerFaction.MONSTER
	):
		_fail("Monster menu choice did not persist into Battle.")
		return false
	var fog := battle.get_node("FogOfWarManager") as FogOfWarManager
	var human_ai := battle.get_node("HumanAIController") as HumanAIController
	var monster_ai := battle.get_node(
		"MonsterAIController"
	) as MonsterAIController
	var selection := battle.get_node(
		"SelectionManager"
	) as UnitSelectionManager
	var hud := battle.get_node("HUDLayer/BattleHUD") as Control
	if (
		fog.get_viewer_faction() != FogOfWarManager.ViewerFaction.MONSTER
		or not human_ai.is_ai_enabled()
		or monster_ai.is_ai_enabled()
		or selection.get_controlled_faction()
		!= FactionComponent.Faction.MONSTER
	):
		_fail("Monster session vision, control, or opponent AI was inverted.")
		return false
	if not _validate_locked_hud(hud, false):
		return false
	var view_button := hud.get_node("TopBar/ViewModeButton") as Button
	view_button.pressed.emit()
	if fog.get_viewer_faction() != FogOfWarManager.ViewerFaction.MONSTER:
		_fail("Locked Monster player could switch to Human vision.")
		return false

	var production := battle.get_node(
		"MonsterProductionManager"
	) as MonsterProductionManager
	var monster_economy := battle.get_node(
		"MonsterEconomy"
	) as MonsterEconomy
	var map := battle.get_node("MVPMap")
	monster_economy.set_process(false)
	monster_economy.add_dark_energy(500, &"t26_monster_validation")
	var nest := map.call("get_active_nests")[0] as Node2D
	if not production.select_nest(nest) or not production.produce(0):
		_fail("Monster player could not select a nest and produce a unit.")
		return false
	var produced := production.get_spawned_monsters()
	var monster_unit := produced[produced.size() - 1]
	var human_unit := _find_living_unit(FactionComponent.Faction.HUMAN)
	selection.select_single(monster_unit)
	if selection.get_selected_units().is_empty():
		_fail("Monster player could not select a produced Monster.")
		return false
	selection.select_single(human_unit)
	if not selection.get_selected_units().is_empty():
		_fail("Monster player was allowed to control a Human unit.")
		return false
	selection.select_single(monster_unit)
	var destination := monster_unit.global_position + Vector2(80.0, 0.0)
	selection.issue_move_command(destination)
	if not monster_unit.call("has_move_target"):
		_fail("Monster player could not issue a movement command.")
		return false
	var adopted_human := false
	for candidate in get_nodes_in_group(&"combat_units"):
		var actor := candidate as Node2D
		var faction := FactionComponent.find_on(actor)
		if (
			faction != null
			and faction.faction == FactionComponent.Faction.HUMAN
			and actor.get_meta(&"human_ai_controlled", false)
		):
			adopted_human = true
			break
	if not adopted_human:
		_fail("Unselected Human starting forces were not handed to Human AI.")
		return false
	return _validate_combat_identity(human_unit, monster_unit)


func _validate_locked_hud(hud: Control, human_selected: bool) -> bool:
	var view_button := hud.get_node("TopBar/ViewModeButton") as Button
	var tower_bar := hud.get_node("TowerBuildBar") as ColorRect
	var squad_bar := hud.get_node("SquadRecruitBar") as ColorRect
	var monster_commands := hud.get_node("MonsterCommandPanel") as ColorRect
	if (
		not hud.call("is_faction_locked")
		or not view_button.disabled
		or ("人类" in view_button.text) != human_selected
		or tower_bar.visible != human_selected
		or squad_bar.visible != human_selected
		or monster_commands.visible == human_selected
	):
		_fail("HUD exposed commands or vision belonging to the opposing faction.")
		return false
	return true


func _validate_combat_identity(
	human_unit: Node2D, monster_unit: Node2D
) -> bool:
	var human_faction := FactionComponent.find_on(human_unit)
	var monster_faction := FactionComponent.find_on(monster_unit)
	if (
		human_faction == null
		or monster_faction == null
		or not human_faction.is_hostile_to(monster_faction)
		or not monster_faction.is_hostile_to(human_faction)
		or CombatRules.are_allies(human_unit, monster_unit)
		or not CombatRules.are_allies(human_unit, human_unit)
		or not CombatRules.are_allies(monster_unit, monster_unit)
		or CombatRules.can_damage(human_unit, human_unit)
		or CombatRules.can_damage(monster_unit, monster_unit)
	):
		_fail("Faction selection changed hostile/friendly combat rules.")
		return false
	return true


func _find_living_unit(faction_value: FactionComponent.Faction) -> Node2D:
	for candidate in get_nodes_in_group(&"combat_units"):
		var unit := candidate as Node2D
		var faction := FactionComponent.find_on(unit)
		var health := unit.get_node_or_null("HealthComponent") as HealthComponent
		if (
			faction != null
			and faction.faction == faction_value
			and (health == null or not health.is_dead)
		):
			return unit
	return null


func _count_living_units(
	faction_value: FactionComponent.Faction
) -> int:
	var count := 0
	for candidate in get_nodes_in_group(&"combat_units"):
		var unit := candidate as Node2D
		var faction := FactionComponent.find_on(unit)
		var health := unit.get_node_or_null("HealthComponent") as HealthComponent
		if (
			faction != null
			and faction.faction == faction_value
			and (health == null or not health.is_dead)
		):
			count += 1
	return count


func _produce_test_monster(battle: Node) -> Node2D:
	var production := battle.get_node(
		"MonsterProductionManager"
	) as MonsterProductionManager
	var economy := battle.get_node("MonsterEconomy") as MonsterEconomy
	var map := battle.get_node("MVPMap")
	economy.set_process(false)
	economy.add_dark_energy(100, &"t26_human_validation")
	var nests: Array[Node2D] = map.call("get_active_nests")
	if nests.is_empty() or not production.produce_from_nest(0, nests[0]):
		return null
	var produced := production.get_spawned_monsters()
	return produced[produced.size() - 1] if not produced.is_empty() else null


func _fail(message: String) -> void:
	push_error("T26 validation failed: %s" % message)
	quit(1)
