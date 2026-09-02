class_name UnitSelectionManager
extends Node2D

## Handles mouse selection and formation-based movement commands.

signal selection_changed(units: Array[Node2D])
signal command_issued(
	command_type: StringName, units: Array[Node2D], target: Variant
)

@export var drag_threshold := 8.0
@export var formation_spacing := 48.0

var selected_units: Array[Node2D] = []
var _drag_start := Vector2.ZERO
var _drag_current := Vector2.ZERO
var _is_dragging := false
var _fog_of_war_manager: FogOfWarManager
var _controlled_faction := FactionComponent.Faction.NEUTRAL
var _player_input_enabled := true


func _ready() -> void:
	add_to_group(&"unit_selection_manager")
	call_deferred("_bind_view_manager")


func _unhandled_input(event: InputEvent) -> void:
	if not _player_input_enabled:
		return
	if _is_build_mode_active():
		if _is_dragging:
			_is_dragging = false
			queue_redraw()
		return

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
			issue_context_command(world_position, mouse_event.shift_pressed)

	elif event is InputEventMouseMotion and _is_dragging:
		var motion_event := event as InputEventMouseMotion
		_drag_current = _screen_to_world(motion_event.position)
		queue_redraw()


func _draw() -> void:
	_draw_selected_route()
	if _is_dragging:
		var selection_rect := _get_drag_rect()
		draw_rect(selection_rect, Color(0.2, 0.65, 1.0, 0.16), true)
		draw_rect(selection_rect, Color(0.35, 0.8, 1.0, 0.9), false, 2.0)


func _process(_delta: float) -> void:
	if _get_route_preview_unit() != null:
		queue_redraw()


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
	if not _is_selectable_for_current_view(unit):
		clear_selection()
		return
	_set_selection([unit])


func select_units(units: Array[Node2D]) -> void:
	var allowed_units: Array[Node2D] = []
	for unit in units:
		if _is_selectable_for_current_view(unit) and not allowed_units.has(unit):
			allowed_units.append(unit)
	_set_selection(allowed_units)


func clear_selection() -> void:
	_clear_selection_state()
	selection_changed.emit([])
	queue_redraw()


func _clear_selection_state() -> void:
	for unit in selected_units:
		if is_instance_valid(unit):
			unit.call("set_selected", false)
	selected_units.clear()


func issue_context_command(
	world_position: Vector2, append_to_route := false
) -> void:
	_remove_invalid_selected_units()
	if selected_units.is_empty():
		return
	if _get_selected_faction() == FactionComponent.Faction.MONSTER:
		var target := _find_hostile_command_target(world_position)
		if target != null:
			if append_to_route:
				issue_route_attack_command(target)
			else:
				issue_attack_command(target)
			return
		if append_to_route:
			issue_waypoint_command(world_position)
			return
	issue_move_command(world_position)


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
		var offset := _get_formation_offset(
			unit_index, columns, formation_size
		)
		selected_units[unit_index].call("move_to", world_position + offset)
	command_issued.emit(&"move", selected_units.duplicate(), world_position)
	queue_redraw()


func issue_rally_command(world_position: Vector2) -> void:
	issue_move_command(world_position)


func issue_attack_command(target: Node2D) -> bool:
	_remove_invalid_selected_units()
	if selected_units.is_empty() or target == null:
		return false
	var commanded_units: Array[Node2D] = []
	for unit in selected_units:
		if CombatRules.can_damage(unit, target) and unit.has_method("attack_target"):
			unit.call("attack_target", target)
			commanded_units.append(unit)
	if commanded_units.is_empty():
		return false
	command_issued.emit(&"attack", commanded_units, target)
	queue_redraw()
	return true


func issue_waypoint_command(world_position: Vector2) -> bool:
	_remove_invalid_selected_units()
	if selected_units.is_empty():
		return false
	var unit_count := selected_units.size()
	var columns := int(ceil(sqrt(float(unit_count))))
	var rows := int(ceil(float(unit_count) / float(columns)))
	var formation_size := Vector2(
		float(columns - 1) * formation_spacing,
		float(rows - 1) * formation_spacing
	)
	var commanded_units: Array[Node2D] = []
	for unit_index in unit_count:
		var unit := selected_units[unit_index]
		if not unit.has_method("append_waypoint"):
			continue
		var offset := _get_formation_offset(
			unit_index, columns, formation_size
		)
		unit.call("append_waypoint", world_position + offset)
		commanded_units.append(unit)
	if commanded_units.is_empty():
		return false
	command_issued.emit(&"waypoint", commanded_units, world_position)
	queue_redraw()
	return true


func issue_route_attack_command(target: Node2D) -> bool:
	_remove_invalid_selected_units()
	if selected_units.is_empty() or target == null:
		return false
	var commanded_units: Array[Node2D] = []
	for unit in selected_units:
		if (
			CombatRules.can_damage(unit, target)
			and unit.has_method("append_route_attack_target")
			and unit.call("append_route_attack_target", target)
		):
			commanded_units.append(unit)
	if commanded_units.is_empty():
		return false
	command_issued.emit(&"route_attack", commanded_units, target)
	queue_redraw()
	return true


func get_selected_units() -> Array[Node2D]:
	_remove_invalid_selected_units()
	return selected_units.duplicate()


func set_controlled_faction(faction: FactionComponent.Faction) -> void:
	_controlled_faction = faction
	clear_selection()


func get_controlled_faction() -> FactionComponent.Faction:
	return _get_controlled_faction()


func set_player_input_enabled(value: bool) -> void:
	_player_input_enabled = value
	if not value:
		clear_selection()


func _set_selection(units: Array[Node2D]) -> void:
	_clear_selection_state()
	for unit in _expand_squad_members(units):
		if not _is_selectable_for_current_view(unit):
			continue
		unit.call("set_selected", true)
		selected_units.append(unit)
	selection_changed.emit(selected_units.duplicate())
	queue_redraw()


func _expand_squad_members(units: Array[Node2D]) -> Array[Node2D]:
	var expanded: Array[Node2D] = []
	var squad_ids: Dictionary[StringName, bool] = {}
	for unit in units:
		if not expanded.has(unit):
			expanded.append(unit)
		if unit.has_method("get_squad_instance_id"):
			var squad_id: StringName = unit.call("get_squad_instance_id")
			if not squad_id.is_empty():
				squad_ids[squad_id] = true
	if squad_ids.is_empty():
		return expanded
	for candidate in _get_selectable_units():
		if not candidate.has_method("get_squad_instance_id"):
			continue
		var candidate_squad_id: StringName = candidate.call(
			"get_squad_instance_id"
		)
		if squad_ids.has(candidate_squad_id) and not expanded.has(candidate):
			expanded.append(candidate)
	return expanded


func _get_selectable_units() -> Array[Node2D]:
	var units: Array[Node2D] = []
	for node in get_tree().get_nodes_in_group("selectable_units"):
		var unit := node as Node2D
		if _is_selectable_for_current_view(unit):
			units.append(unit)
	return units


func _remove_invalid_selected_units() -> void:
	for unit_index in range(selected_units.size() - 1, -1, -1):
		if (
			not is_instance_valid(selected_units[unit_index])
			or not selected_units[unit_index].is_in_group("selectable_units")
		):
			selected_units.remove_at(unit_index)


func _get_drag_rect() -> Rect2:
	return Rect2(_drag_start, _drag_current - _drag_start).abs()


func _screen_to_world(screen_position: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen_position


func _is_build_mode_active() -> bool:
	var placement_manager := get_tree().get_first_node_in_group(
		&"building_placement_manager"
	)
	return (
		placement_manager != null
		and placement_manager.call("is_build_mode_active")
	)


func _is_selectable_for_current_view(unit: Node2D) -> bool:
	if (
		unit == null
		or not is_instance_valid(unit)
		or not unit.is_in_group(&"selectable_units")
		or not unit.visible
	):
		return false
	var faction := FactionComponent.find_on(unit)
	return faction != null and faction.faction == _get_controlled_faction()


func _get_controlled_faction() -> FactionComponent.Faction:
	if _controlled_faction != FactionComponent.Faction.NEUTRAL:
		return _controlled_faction as FactionComponent.Faction
	var fog_manager := _fog_of_war_manager
	if fog_manager == null or not is_instance_valid(fog_manager):
		fog_manager = get_tree().get_first_node_in_group(&"human_fog_manager")
	if (
		fog_manager != null
		and fog_manager.call("get_viewer_faction")
		== FogOfWarManager.ViewerFaction.MONSTER
	):
		return FactionComponent.Faction.MONSTER
	return FactionComponent.Faction.HUMAN


func _bind_view_manager() -> void:
	_fog_of_war_manager = get_tree().get_first_node_in_group(
		&"human_fog_manager"
	) as FogOfWarManager
	if (
		_fog_of_war_manager != null
		and not _fog_of_war_manager.viewer_faction_changed.is_connected(
			_on_viewer_faction_changed
		)
	):
		_fog_of_war_manager.viewer_faction_changed.connect(
			_on_viewer_faction_changed
		)


func _on_viewer_faction_changed(
	_viewer_faction: FogOfWarManager.ViewerFaction
) -> void:
	clear_selection()


func _get_selected_faction() -> FactionComponent.Faction:
	if selected_units.is_empty():
		return FactionComponent.Faction.NEUTRAL
	var faction := FactionComponent.find_on(selected_units[0])
	return (
		FactionComponent.Faction.NEUTRAL
		if faction == null
		else faction.faction
	)


func _find_hostile_command_target(world_position: Vector2) -> Node2D:
	var nearest_target: Node2D
	var nearest_distance := INF
	for candidate_node in get_tree().get_nodes_in_group(&"combat_targets"):
		var candidate := candidate_node as Node2D
		if candidate == null or not candidate.visible:
			continue
		var click_radius := _get_target_click_radius(candidate)
		var distance := candidate.global_position.distance_to(world_position)
		if (
			distance <= click_radius
			and distance < nearest_distance
			and CombatRules.can_damage(selected_units[0], candidate)
		):
			nearest_target = candidate
			nearest_distance = distance
	return nearest_target


func _get_target_click_radius(target: Node2D) -> float:
	if target.has_method("get_selection_radius"):
		return maxf(float(target.call("get_selection_radius")), 24.0)
	var footprint := target.get_node_or_null("BuildingFootprint")
	if footprint != null:
		return maxf(float(footprint.get("radius")) + 10.0, 30.0)
	return 30.0


func _get_formation_offset(
	unit_index: int, columns: int, formation_size: Vector2
) -> Vector2:
	var column := unit_index % columns
	var row := unit_index / columns
	return Vector2(
		float(column) * formation_spacing,
		float(row) * formation_spacing
	) - formation_size * 0.5


func _get_route_preview_unit() -> Node2D:
	for unit in selected_units:
		if (
			is_instance_valid(unit)
			and unit.has_method("get_waypoint_route")
			and (
				not (unit.call("get_waypoint_route") as Array).is_empty()
				or unit.call("get_route_attack_target") != null
			)
		):
			return unit
	return null


func _draw_selected_route() -> void:
	var unit := _get_route_preview_unit()
	if unit == null:
		return
	var route: Array = unit.call("get_waypoint_route")
	var points := PackedVector2Array([unit.global_position])
	for route_point in route:
		points.append(route_point as Vector2)
	var attack_target := unit.call("get_route_attack_target") as Node2D
	if attack_target != null:
		points.append(attack_target.global_position)
	if points.size() >= 2:
		draw_polyline(points, Color(0.9, 0.35, 1.0, 0.9), 3.0, true)
	for index in route.size():
		var point := route[index] as Vector2
		draw_circle(point, 10.0, Color(0.55, 0.15, 0.75, 0.9))
		draw_circle(point, 10.0, Color(1.0, 0.65, 1.0, 1.0), false, 2.0)
		draw_string(
			ThemeDB.fallback_font,
			point + Vector2(-4.0, 5.0),
			str(index + 1),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			12,
			Color.WHITE
		)
	if attack_target != null:
		var target_position := attack_target.global_position
		draw_circle(target_position, 15.0, Color(1.0, 0.2, 0.35, 0.95), false, 3.0)
		draw_line(
			target_position + Vector2(-10.0, -10.0),
			target_position + Vector2(10.0, 10.0),
			Color(1.0, 0.2, 0.35, 0.95),
			3.0
		)
		draw_line(
			target_position + Vector2(10.0, -10.0),
			target_position + Vector2(-10.0, 10.0),
			Color(1.0, 0.2, 0.35, 0.95),
			3.0
		)
