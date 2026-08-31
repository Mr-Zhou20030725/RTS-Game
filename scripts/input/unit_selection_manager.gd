class_name UnitSelectionManager
extends Node2D

## Handles mouse selection and formation-based movement commands.

@export var drag_threshold := 8.0
@export var formation_spacing := 48.0

var selected_units: Array[Node2D] = []
var _drag_start := Vector2.ZERO
var _drag_current := Vector2.ZERO
var _is_dragging := false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		var world_position := _screen_to_world(mouse_event.position)

		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				_drag_start = world_position
				_drag_current = world_position
				_is_dragging = true
				queue_redraw()
			elif _is_dragging:
				_drag_current = world_position
				var drag_distance := _drag_start.distance_to(_drag_current)
				if drag_distance >= drag_threshold:
					select_in_rect(_get_drag_rect())
				else:
					select_at_point(world_position)
				_is_dragging = false
				queue_redraw()

		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			issue_move_command(world_position)

	elif event is InputEventMouseMotion and _is_dragging:
		var motion_event := event as InputEventMouseMotion
		_drag_current = _screen_to_world(motion_event.position)
		queue_redraw()


func _draw() -> void:
	if not _is_dragging:
		return
	var selection_rect := _get_drag_rect()
	draw_rect(selection_rect, Color(0.2, 0.65, 1.0, 0.16), true)
	draw_rect(selection_rect, Color(0.35, 0.8, 1.0, 0.9), false, 2.0)


func select_at_point(world_position: Vector2) -> void:
	var nearest_unit: Node2D
	var nearest_distance := INF

	for unit in _get_selectable_units():
		var click_radius: float = unit.call("get_selection_radius")
		var distance := unit.global_position.distance_to(world_position)
		if distance <= click_radius and distance < nearest_distance:
			nearest_unit = unit
			nearest_distance = distance

	if nearest_unit == null:
		clear_selection()
	else:
		_set_selection([nearest_unit])


func select_in_rect(selection_rect: Rect2) -> void:
	var units_in_rect: Array[Node2D] = []
	for unit in _get_selectable_units():
		if selection_rect.has_point(unit.global_position):
			units_in_rect.append(unit)
	_set_selection(units_in_rect)


func select_single(unit: Node2D) -> void:
	if unit == null or not unit.is_in_group("selectable_units"):
		clear_selection()
		return
	_set_selection([unit])


func clear_selection() -> void:
	for unit in selected_units:
		if is_instance_valid(unit):
			unit.call("set_selected", false)
	selected_units.clear()


func issue_move_command(world_position: Vector2) -> void:
	_remove_invalid_selected_units()
	if selected_units.is_empty():
		return

	var unit_count := selected_units.size()
	var columns := int(ceil(sqrt(float(unit_count))))
	var rows := int(ceil(float(unit_count) / float(columns)))
	var formation_size := Vector2(
		float(columns - 1) * formation_spacing,
		float(rows - 1) * formation_spacing
	)

	for unit_index in unit_count:
		var column := unit_index % columns
		var row := unit_index / columns
		var offset := Vector2(
			float(column) * formation_spacing,
			float(row) * formation_spacing
		) - formation_size * 0.5
		selected_units[unit_index].call("move_to", world_position + offset)


func get_selected_units() -> Array[Node2D]:
	_remove_invalid_selected_units()
	return selected_units.duplicate()


func _set_selection(units: Array[Node2D]) -> void:
	clear_selection()
	for unit in units:
		if not is_instance_valid(unit):
			continue
		unit.call("set_selected", true)
		selected_units.append(unit)


func _get_selectable_units() -> Array[Node2D]:
	var units: Array[Node2D] = []
	for node in get_tree().get_nodes_in_group("selectable_units"):
		if node is Node2D and is_instance_valid(node):
			units.append(node)
	return units


func _remove_invalid_selected_units() -> void:
	for unit_index in range(selected_units.size() - 1, -1, -1):
		if not is_instance_valid(selected_units[unit_index]):
			selected_units.remove_at(unit_index)


func _get_drag_rect() -> Rect2:
	return Rect2(_drag_start, _drag_current - _drag_start).abs()


func _screen_to_world(screen_position: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen_position
