extends SceneTree

const BATTLE_SCENE := preload("res://scenes/battle/battle.tscn")


func _init() -> void:
	_run_validation()


func _run_validation() -> void:
	var battle := BATTLE_SCENE.instantiate()
	root.add_child(battle)
	await process_frame
	await process_frame
	var fog := battle.get_node("FogOfWarManager") as FogOfWarManager
	var map := battle.get_node("MVPMap")
	var production := battle.get_node(
		"MonsterProductionManager"
	) as MonsterProductionManager
	var hud := battle.get_node("HUDLayer/BattleHUD") as Control
	var button := hud.get_node("TopBar/ViewModeButton") as Button
	var panel := hud.get_node("MonsterProductionPanel") as ColorRect
	if (
		fog == null
		or production == null
		or button == null
		or fog.get_viewer_faction() != FogOfWarManager.ViewerFaction.HUMAN
		or not fog.canvas_modulate.visible
		or button.text != "VIEW: HUMAN"
	):
		_fail("Battle did not start in the Human fog view.")
		return

	var hidden_nest := _find_hidden_nest(map, fog)
	var human_unit := _find_faction_unit(FactionComponent.Faction.HUMAN)
	var hidden_monster := _find_faction_unit(FactionComponent.Faction.MONSTER)
	if hidden_nest == null or human_unit == null or hidden_monster == null:
		_fail("Could not locate the hidden nest and faction units needed by T21.")
		return
	hidden_monster.global_position = hidden_nest.global_position
	fog.refresh_visibility()
	if hidden_nest.visible or hidden_monster.visible:
		_fail("Human view exposed a target outside all Human vision sources.")
		return
	if (
		fog.is_node_visible_to_human(hidden_monster)
		or CombatRules.can_damage(human_unit, hidden_monster)
	):
		_fail("Human visibility or targeting rules accepted a hidden monster.")
		return

	button.pressed.emit()
	await process_frame
	if (
		fog.get_viewer_faction() != FogOfWarManager.ViewerFaction.MONSTER
		or fog.canvas_modulate.visible
		or button.text != "VIEW: MONSTER"
		or not hidden_nest.visible
		or not hidden_monster.visible
	):
		_fail("Monster view did not reveal the full battlefield without fog.")
		return
	if not _all_human_assets_visible():
		_fail("Monster view did not show all Human buildings and major units.")
		return
	if (
		fog.is_node_visible_to_human(hidden_monster)
		or CombatRules.can_damage(human_unit, hidden_monster)
	):
		_fail("Changing presentation incorrectly changed Human combat rules.")
		return

	if not production.select_nest(hidden_nest) or not panel.visible:
		_fail("A visible nest could not be selected in Monster view.")
		return
	button.pressed.emit()
	await process_frame
	if (
		fog.get_viewer_faction() != FogOfWarManager.ViewerFaction.HUMAN
		or not fog.canvas_modulate.visible
		or button.text != "VIEW: HUMAN"
		or hidden_nest.visible
		or hidden_monster.visible
		or production.get_selected_nest() != null
		or panel.visible
	):
		_fail("Returning to Human view did not restore fog or clear leaked UI.")
		return

	print(
		"T21 validation passed: Monster view reveals the whole map and all "
		+ "Human assets, while Human fog, targeting, and hidden-nest UI rules "
		+ "remain unchanged when views switch."
	)
	quit()


func _find_hidden_nest(map: Node, fog: FogOfWarManager) -> Node2D:
	for value in map.call("get_active_nests"):
		var nest := value as Node2D
		if nest != null and not fog.is_node_visible_to_human(nest):
			return nest
	return null


func _find_faction_unit(faction_value: FactionComponent.Faction) -> Node2D:
	for candidate in get_nodes_in_group(&"combat_units"):
		if not candidate is Node2D:
			continue
		var faction := FactionComponent.find_on(candidate)
		if faction != null and faction.faction == faction_value:
			return candidate as Node2D
	return null


func _all_human_assets_visible() -> bool:
	for group_name in [&"combat_units", &"combat_buildings"]:
		for candidate in get_nodes_in_group(group_name):
			if not candidate is CanvasItem:
				continue
			var faction := FactionComponent.find_on(candidate)
			if (
				faction != null
				and faction.faction == FactionComponent.Faction.HUMAN
				and not (candidate as CanvasItem).visible
			):
				return false
	return true


func _fail(message: String) -> void:
	push_error("T21 validation failed: %s" % message)
	quit(1)
