class_name BuildingPlacementManager
extends Node2D

## Owns construction preview, validation, cancellation, and atomic spending.

signal build_mode_changed(active: bool)
signal preview_validity_changed(is_valid: bool)
signal building_placed(building: Node2D, cost: int)
signal placement_failed(reason: StringName)

@export var default_building_scene: PackedScene
@export_range(0, 1000000, 1) var default_building_cost := 50
@export var buildable_bounds := Rect2(80.0, 96.0, 1120.0, 576.0)
@export_range(0.0, 100.0, 1.0) var overlap_padding := 8.0
@export_range(1.0, 128.0, 1.0) var grid_size := 16.0
@export var valid_preview_color := Color(0.35, 1.0, 0.45, 0.68)
@export var invalid_preview_color := Color(1.0, 0.25, 0.25, 0.68)

var human_economy: Node
var _preview: Node2D
var _preview_is_valid := false
var _active_cost := 0
var _placed_buildings: Array[Node2D] = []
var _building_serial := 0


func _ready() -> void:
	call_deferred("_bind_human_economy")


func _unhandled_input(event: InputEvent) -> void:
	if not is_build_mode_active():
		return

	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		update_preview_position(_screen_to_world(motion.position))
		get_viewport().set_input_as_handled()
		return

	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed:
		return

	if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		cancel_placement()
		get_viewport().set_input_as_handled()
	elif mouse_event.button_index == MOUSE_BUTTON_LEFT:
		update_preview_position(_screen_to_world(mouse_event.position))
		confirm_placement()
		get_viewport().set_input_as_handled()


func begin_default_placement() -> bool:
	return begin_placement(
		default_building_scene,
		default_building_cost,
		get_global_mouse_position()
	)


func begin_placement(
	building_scene: PackedScene, cost: int, world_position: Vector2
) -> bool:
	if building_scene == null or cost < 0:
		placement_failed.emit(&"invalid_configuration")
		return false
	_bind_human_economy()
	if human_economy == null or not human_economy.call("can_afford", cost):
		placement_failed.emit(&"not_enough_gold")
		return false

	if is_build_mode_active():
		cancel_placement()
	_preview = building_scene.instantiate() as Node2D
	if _preview == null:
		placement_failed.emit(&"invalid_building_scene")
		return false

	_active_cost = cost
	add_child(_preview)
	update_preview_position(world_position)
	build_mode_changed.emit(true)
	return true


func update_preview_position(world_position: Vector2) -> void:
	if _preview == null:
		return
	_preview.global_position = _snap_to_grid(world_position)
	_set_preview_validity(_is_position_valid(_preview.global_position))


func confirm_placement() -> bool:
	if _preview == null:
		return false
	update_preview_position(_preview.global_position)
	if not _preview_is_valid:
		placement_failed.emit(&"invalid_position")
		return false
	_bind_human_economy()
	if (
		human_economy == null
		or not human_economy.call(
			"try_spend", _active_cost, &"tower_construction"
		)
	):
		placement_failed.emit(&"not_enough_gold")
		return false

	var placed_building := _preview
	_preview = null
	_preview_is_valid = false
	_building_serial += 1
	placed_building.name = "PlacedTower_%02d" % _building_serial
	placed_building.modulate = Color.WHITE
	placed_building.add_to_group(&"placed_towers")
	_placed_buildings.append(placed_building)
	var paid_cost := _active_cost
	_active_cost = 0
	build_mode_changed.emit(false)
	building_placed.emit(placed_building, paid_cost)
	return true


func cancel_placement() -> void:
	if _preview == null:
		return
	var cancelled_preview := _preview
	_preview = null
	_preview_is_valid = false
	_active_cost = 0
	remove_child(cancelled_preview)
	cancelled_preview.queue_free()
	build_mode_changed.emit(false)


func is_build_mode_active() -> bool:
	return _preview != null and is_instance_valid(_preview)


func is_preview_position_valid() -> bool:
	return is_build_mode_active() and _preview_is_valid


func get_preview() -> Node2D:
	return _preview


func get_placed_buildings() -> Array[Node2D]:
	for index in range(_placed_buildings.size() - 1, -1, -1):
		if not is_instance_valid(_placed_buildings[index]):
			_placed_buildings.remove_at(index)
	return _placed_buildings.duplicate()


func _bind_human_economy() -> void:
	if human_economy != null and is_instance_valid(human_economy):
		return
	human_economy = get_tree().get_first_node_in_group(&"human_economy")


func _is_position_valid(world_position: Vector2) -> bool:
	var preview_radius := _get_footprint_radius(_preview)
	var inner_bounds := buildable_bounds.grow(-preview_radius)
	if not inner_bounds.has_point(world_position):
		return false

	for blocker_node in get_tree().get_nodes_in_group(&"placement_blockers"):
		if blocker_node == _preview or not blocker_node is Node2D:
			continue
		var blocker := blocker_node as Node2D
		if not is_instance_valid(blocker) or not blocker.is_inside_tree():
			continue
		var required_distance := (
			preview_radius
			+ _get_footprint_radius(blocker)
			+ overlap_padding
		)
		if world_position.distance_to(blocker.global_position) < required_distance:
			return false
	return true


func _get_footprint_radius(building: Node2D) -> float:
	if building == null:
		return 32.0
	var footprint := building.get_node_or_null("BuildingFootprint")
	if footprint == null:
		return 32.0
	return maxf(float(footprint.get("radius")), 1.0)


func _set_preview_validity(value: bool) -> void:
	_preview_is_valid = value
	_preview.modulate = valid_preview_color if value else invalid_preview_color
	preview_validity_changed.emit(value)


func _snap_to_grid(world_position: Vector2) -> Vector2:
	return Vector2(
		roundf(world_position.x / grid_size) * grid_size,
		roundf(world_position.y / grid_size) * grid_size
	)


func _screen_to_world(screen_position: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen_position
