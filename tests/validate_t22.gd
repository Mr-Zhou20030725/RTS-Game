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
	var hud := battle.get_node("HUDLayer/BattleHUD") as Control
	var command_panel := hud.get_node("MonsterCommandPanel") as ColorRect
	if (
		fog == null
		or production == null
		or selection == null
		or legions == null
		or command_panel == null
	):
		_fail("Battle is missing a T22 manager or HUD panel.")
		return

	economy.set_process(false)
	economy.add_dark_energy(800, &"t22_validation")
	var nest := map.call("get_active_nests")[0] as Node2D
	production.select_nest(nest)
	var catalog_indices := [0, 2, 1, 3]
	var monsters: Array[Node2D] = []
	for catalog_index in catalog_indices:
		if not production.produce(catalog_index):
			_fail("Could not produce the mixed Monster roster for legion testing.")
			return
		var spawned := production.get_spawned_monsters()
		monsters.append(spawned[spawned.size() - 1])

	fog.set_viewer_faction(FogOfWarManager.ViewerFaction.MONSTER)
	await process_frame
	if not command_panel.visible:
		_fail("Monster view did not expose the legion command panel.")
		return
	var team_one_positions := [Vector2(870.0, 150.0), Vector2(930.0, 150.0)]
	var team_two_positions := [Vector2(160.0, 580.0), Vector2(220.0, 580.0)]
	for index in 2:
		monsters[index].global_position = team_one_positions[index]
		monsters[index + 2].global_position = team_two_positions[index]
		monsters[index].call("stop_moving")
		monsters[index + 2].call("stop_moving")

	selection.select_in_rect(Rect2(Vector2(830.0, 110.0), Vector2(140.0, 80.0)))
	if selection.get_selected_units().size() != 2:
		_fail("Monster box selection did not select exactly the mixed first army.")
		return
	var create_button := command_panel.get_node("CreateLegionButton") as Button
	create_button.pressed.emit()
	await process_frame
	if not _validate_legion(legions, 1, [monsters[0], monsters[1]]):
		return

	selection.select_in_rect(Rect2(Vector2(120.0, 540.0), Vector2(140.0, 80.0)))
	if not legions.create_legion(2):
		_fail("Could not create a second independent Monster legion.")
		return
	if not _validate_legion(legions, 2, [monsters[2], monsters[3]]):
		return

	if not legions.select_legion(1):
		_fail("Legion 1 could not be recalled.")
		return
	var rally_one := Vector2(990.0, 260.0)
	selection.issue_rally_command(rally_one)
	if not _has_formation_orders(legions.get_legion_units(1), rally_one):
		_fail("Legion 1 did not receive a separated rally formation.")
		return
	for unit in legions.get_legion_units(2):
		if unit.call("is_manual_move_order_active"):
			_fail("Rallying Legion 1 also moved Legion 2.")
			return

	var human_base := map.get("human_base") as Node2D
	if human_base == null:
		_fail("Could not locate the Human base attack target.")
		return
	selection.issue_context_command(human_base.global_position)
	if legions.get_legion_units(1)[0].call("get_command_target") != human_base:
		_fail("Legion 1 could not receive an explicit Human-base attack order.")
		return
	for unit in legions.get_legion_units(1):
		if unit.call("get_command_target") != human_base:
			_fail("A mixed melee/ranged Legion member lost its attack target.")
			return

	if not legions.select_legion(2):
		_fail("Legion 2 could not be recalled independently.")
		return
	var rally_two := Vector2(180.0, 300.0)
	selection.issue_rally_command(rally_two)
	if not _has_formation_orders(legions.get_legion_units(2), rally_two):
		_fail("Legion 2 did not receive its independent rally order.")
		return
	for unit in legions.get_legion_units(1):
		if unit.call("get_command_target") != human_base:
			_fail("Commanding Legion 2 overwrote Legion 1's attack order.")
			return

	fog.set_viewer_faction(FogOfWarManager.ViewerFaction.HUMAN)
	selection.select_units(monsters)
	if not selection.get_selected_units().is_empty():
		_fail("Human view was able to select Monster legion members.")
		return

	print(
		"T22 validation passed: Monster box selection creates mixed persistent "
		+ "legions, rally and explicit building attack orders work, and two "
		+ "legions retain independent commands."
	)
	quit()


func _validate_legion(
	manager: MonsterLegionManager, slot: int, expected_units: Array
) -> bool:
	var units := manager.get_legion_units(slot)
	if units.size() != expected_units.size():
		_fail("Legion %d contains an unexpected number of units." % slot)
		return false
	for expected_unit in expected_units:
		if (
			not units.has(expected_unit)
			or expected_unit.call("get_legion_slot") != slot
			or not expected_unit.get_node("LegionBadge").visible
		):
			_fail("Legion membership or its world badge is incorrect.")
			return false
	return true


func _has_formation_orders(units: Array[Node2D], center: Vector2) -> bool:
	var destinations: Dictionary[Vector2, bool] = {}
	for unit in units:
		if not unit.call("is_manual_move_order_active"):
			return false
		var destination: Vector2 = unit.call("get_move_target")
		if destination.distance_to(center) > 80.0:
			return false
		destinations[destination] = true
	return destinations.size() == units.size()


func _fail(message: String) -> void:
	push_error("T22 validation failed: %s" % message)
	quit(1)
