extends SceneTree

const BATTLE_SCENE := preload("res://scenes/battle/battle.tscn")
const EXPECTED_UNIT_COUNT := 6


func _init() -> void:
	_run_validation()


func _run_validation() -> void:
	var battle := BATTLE_SCENE.instantiate()
	root.add_child(battle)
	await process_frame
	await physics_frame
	await physics_frame

	var selection_manager := battle.get_node_or_null("SelectionManager")
	if selection_manager == null:
		_fail("Battle scene does not contain SelectionManager.")
		return

	var units := get_nodes_in_group("selectable_units")
	if units.size() != EXPECTED_UNIT_COUNT:
		_fail("Battle scene does not contain the expected 6 selectable units.")
		return

	_simulate_left_click(selection_manager, units[0].global_position)
	var selected_units: Array = selection_manager.call("get_selected_units")
	if selected_units.size() != 1 or selected_units[0] != units[0]:
		_fail("Mouse single selection did not select exactly one unit.")
		return
	if not units[0].get("is_selected"):
		_fail("Selected unit did not show its selected state.")
		return

	_simulate_box_selection(
		selection_manager,
		Vector2(430.0, 280.0),
		Vector2(560.0, 450.0)
	)
	selected_units = selection_manager.call("get_selected_units")
	if selected_units.size() != EXPECTED_UNIT_COUNT:
		_fail("Mouse box selection did not select all 6 units.")
		return

	var starting_positions: Array[Vector2] = []
	for unit in selected_units:
		starting_positions.append(unit.global_position)

	var first_destination := Vector2(930.0, 430.0)
	_simulate_right_click(selection_manager, first_destination)
	if not _move_targets_are_unique(selected_units):
		_fail("Formation command assigned overlapping target positions.")
		return

	for _frame in 180:
		await physics_frame

	for unit_index in selected_units.size():
		if (
			selected_units[unit_index].global_position.distance_to(
				starting_positions[unit_index]
			)
			< 100.0
		):
			_fail("A selected unit did not move toward the command.")
			return

	for unit_index in selected_units.size():
		for other_index in range(unit_index + 1, selected_units.size()):
			if (
				selected_units[unit_index].global_position.distance_to(
					selected_units[other_index].global_position
				)
				< 20.0
			):
				_fail("Units collapsed into the same position after moving.")
				return

	for command_index in 100:
		selection_manager.call(
			"issue_move_command",
			Vector2(
				700.0 + float(command_index % 10) * 12.0,
				220.0 + float(command_index % 7) * 10.0
			)
		)

	var final_destination := Vector2(820.0, 250.0)
	selection_manager.call("issue_move_command", final_destination)
	if not _move_targets_are_unique(selected_units):
		_fail("Rapid commands left units with overlapping targets.")
		return
	for unit in selected_units:
		if unit.call("get_move_target").distance_to(final_destination) > 100.0:
			_fail("Rapid commands did not preserve the final move order.")
			return

	print(
		"T04 validation passed: single select, box select, navigation movement, "
		+ "formation spacing, separation, and 100 rapid commands."
	)
	quit()


func _simulate_left_click(manager: Node, position: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = position
	press.pressed = true
	manager.call("_unhandled_input", press)

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = position
	release.pressed = false
	manager.call("_unhandled_input", release)


func _simulate_box_selection(
	manager: Node, start_position: Vector2, end_position: Vector2
) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = start_position
	press.pressed = true
	manager.call("_unhandled_input", press)

	var motion := InputEventMouseMotion.new()
	motion.position = end_position
	manager.call("_unhandled_input", motion)

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = end_position
	release.pressed = false
	manager.call("_unhandled_input", release)


func _simulate_right_click(manager: Node, position: Vector2) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.position = position
	click.pressed = true
	manager.call("_unhandled_input", click)


func _move_targets_are_unique(units: Array) -> bool:
	var targets: Dictionary = {}
	for unit in units:
		targets[unit.call("get_move_target")] = true
	return targets.size() == units.size()


func _fail(message: String) -> void:
	push_error("T04 validation failed: %s" % message)
	quit(1)
