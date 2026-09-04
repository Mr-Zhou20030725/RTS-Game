extends SceneTree

const BATTLE_SCENE := preload("res://scenes/battle/battle.tscn")


func _init() -> void:
	_run_validation()


func _run_validation() -> void:
	var battle := BATTLE_SCENE.instantiate()
	root.add_child(battle)
	await process_frame
	await process_frame
	await process_frame
	battle.get_node("HumanAIController").call("set_ai_enabled", false)
	battle.get_node("MonsterAIController").call("set_ai_enabled", false)
	var hud := battle.get_node("HUDLayer/BattleHUD") as Control
	var map := battle.get_node("MVPMap") as Node2D
	var selection := battle.get_node("SelectionManager")
	var human_economy := battle.get_node("HumanEconomy") as HumanEconomy
	var monster_economy := battle.get_node("MonsterEconomy") as MonsterEconomy
	var time_manager := battle.get_node("GameTimeManager") as GameTimeManager
	var production := battle.get_node(
		"MonsterProductionManager"
	) as MonsterProductionManager
	if not _validate_overview_fields(hud, battle):
		return

	var human_base := map.get("human_base") as Node2D
	var base_health := human_base.get_node("HealthComponent") as HealthComponent
	base_health.take_damage(125.0)
	if (
		"875 / 1000" not in hud.get_node(
			"SituationBar/BaseHealthLabel"
		).text
	):
		_fail("Human base HP did not update from HealthComponent signals.")
		return

	var nests: Array[Node2D] = map.call("get_active_nests")
	var nest_health := nests[0].get_node("HealthComponent") as HealthComponent
	nest_health.take_damage(nest_health.max_health)
	if "3 / 4" not in hud.get_node("SituationBar/NestCountLabel").text:
		_fail("Living nest count did not update after a nest was destroyed.")
		return

	var human_unit := _find_living_unit(FactionComponent.Faction.HUMAN)
	selection.call("select_single", human_unit)
	await process_frame
	var selected_label := hud.get_node(
		"SituationBar/SelectedUnitsLabel"
	) as Label
	if (
		"选中单位" not in selected_label.text
		or "HP" not in selected_label.text
		or "无" in selected_label.text
	):
		_fail("Selected Human unit composition and HP are not visible.")
		return
	var unit_health := human_unit.get_node("HealthComponent") as HealthComponent
	var previous_text := selected_label.text
	unit_health.take_damage(10.0)
	if selected_label.text == previous_text:
		_fail("Selected unit HP did not refresh after taking damage.")
		return

	var gold_before := human_economy.get_gold()
	var energy_before := monster_economy.get_dark_energy()
	human_economy.add_gold(17, &"t32_test")
	monster_economy.add_dark_energy(19, &"t32_test")
	if (
		str(gold_before + 17) not in hud.get_node("TopBar/GoldLabel").text
		or str(energy_before + 19) not in hud.get_node(
			"TopBar/DarkEnergyLabel"
		).text
	):
		_fail("Both faction resource readouts did not refresh.")
		return
	time_manager.jump_to_time(65.0)
	var time_label := battle.get_node(
		"GameTimeManager/TimeDisplayLayer/TimePanel/TimeLabel"
	) as Label
	if "01:05" not in time_label.text:
		_fail("Game time is not visible in the battle HUD area.")
		return

	hud.call("configure_player_faction", GameManager.PlayerFaction.HUMAN)
	if not _validate_faction_shortcuts(hud, true):
		return
	hud.call("configure_player_faction", GameManager.PlayerFaction.MONSTER)
	if not _validate_faction_shortcuts(hud, false):
		return
	var remaining_nests: Array[Node2D] = map.call("get_active_nests")
	if not production.select_nest(remaining_nests[0]):
		_fail("Could not select a living nest for Monster production HUD validation.")
		return
	if not hud.get_node("MonsterProductionPanel").visible:
		_fail("Monster production shortcut panel did not appear for a selected nest.")
		return
	if not _validate_non_overlapping_layout(hud, battle):
		return

	print(
		"T32 validation passed: faction, resources, time, base HP, nest count, "
		+ "context shortcuts, and live selection details are visible without overlap."
	)
	quit(0)


func _validate_overview_fields(hud: Control, battle: Node) -> bool:
	var required_paths := [
		"TopBar/GoldLabel",
		"TopBar/DarkEnergyLabel",
		"TopBar/ViewModeButton",
		"SituationBar/BaseHealthLabel",
		"SituationBar/NestCountLabel",
		"SituationBar/SelectedUnitsLabel",
		"TowerBuildBar",
		"SquadRecruitBar",
		"MonsterProductionPanel",
	]
	for path in required_paths:
		if hud.get_node_or_null(path) == null:
			_fail("HUD field is missing: %s" % path)
			return false
	if battle.get_node_or_null(
		"GameTimeManager/TimeDisplayLayer/TimePanel/TimeLabel"
	) == null:
		_fail("Game time display is missing.")
		return false
	return true


func _validate_faction_shortcuts(hud: Control, human_selected: bool) -> bool:
	var faction_button := hud.get_node("TopBar/ViewModeButton") as Button
	var tower_bar := hud.get_node("TowerBuildBar") as Control
	var squad_bar := hud.get_node("SquadRecruitBar") as Control
	var monster_commands := hud.get_node("MonsterCommandPanel") as Control
	if (
		("人类" in faction_button.text) != human_selected
		or tower_bar.visible != human_selected
		or squad_bar.visible != human_selected
		or monster_commands.visible == human_selected
	):
		_fail("Faction label or contextual command shortcuts are inconsistent.")
		return false
	return true


func _validate_non_overlapping_layout(hud: Control, battle: Node) -> bool:
	var title := hud.get_node("TopBar/Title") as Control
	var time_panel := battle.get_node(
		"GameTimeManager/TimeDisplayLayer/TimePanel"
	) as Control
	if title.get_global_rect().intersects(time_panel.get_global_rect()):
		_fail("Battle title overlaps the game-time panel.")
		return false
	var overview_controls: Array[Control] = [
		hud.get_node("SituationBar/BaseHealthLabel") as Control,
		hud.get_node("SituationBar/NestCountLabel") as Control,
		hud.get_node("SituationBar/SelectedUnitsLabel") as Control,
	]
	for left_index in overview_controls.size():
		for right_index in range(left_index + 1, overview_controls.size()):
			if overview_controls[left_index].get_global_rect().intersects(
				overview_controls[right_index].get_global_rect()
			):
				_fail("Situation overview fields overlap each other.")
				return false
	var situation_bar := hud.get_node("SituationBar") as Control
	var monster_panel := hud.get_node("MonsterProductionPanel") as Control
	var event_panel := battle.get_node(
		"EventEffectManager/StatusLayer/StatusPanel"
	) as Control
	if (
		situation_bar.get_global_rect().intersects(monster_panel.get_global_rect())
		or situation_bar.get_global_rect().intersects(event_panel.get_global_rect())
	):
		_fail("Situation bar overlaps a persistent command or event panel.")
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
			and health != null
			and not health.is_dead
		):
			return unit
	return null


func _fail(message: String) -> void:
	paused = false
	push_error("T32 validation failed: %s" % message)
	quit(1)
