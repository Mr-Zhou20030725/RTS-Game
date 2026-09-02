class_name MonsterProductionManager
extends Node2D

## Selects active nests and spends dark energy to spawn monsters beside them.

signal nest_selected(nest: Node2D)
signal selection_cleared
signal monster_produced(
	monster: Node2D, nest: Node2D, data: MonsterProductionData, cost: int
)
signal production_failed(reason: StringName)
signal production_costs_changed(multiplier: float)

@export var production_catalog: Array[Resource] = []
@export var battlefield_bounds := Rect2(80.0, 96.0, 1120.0, 576.0)
@export_range(0.0, 128.0, 1.0) var spawn_clearance := 16.0
@export_range(1.0, 128.0, 1.0) var monster_radius := 17.0
@export_range(1.0, 128.0, 1.0) var ring_spacing := 30.0

@onready var spawned_monsters: Node2D = %SpawnedMonsters

var monster_economy: MonsterEconomy
var mvp_map: Node
var selected_nest: Node2D
var _monster_serial := 0
var _production_cost_multiplier := 1.0


func _ready() -> void:
	call_deferred("_bind_dependencies")


func _unhandled_input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
	):
		select_nest_at(get_global_mouse_position(), true)


func get_production_catalog() -> Array[Resource]:
	return production_catalog.duplicate()


func get_effective_cost(catalog_index: int) -> int:
	if catalog_index < 0 or catalog_index >= production_catalog.size():
		return -1
	var data := production_catalog[catalog_index] as MonsterProductionData
	if data == null:
		return -1
	return maxi(roundi(float(data.cost) * _production_cost_multiplier), 0)


func get_production_cost_multiplier() -> float:
	return _production_cost_multiplier


func set_production_cost_multiplier(value: float) -> void:
	var next_multiplier := clampf(value, 0.1, 1.0)
	if is_equal_approx(next_multiplier, _production_cost_multiplier):
		return
	_production_cost_multiplier = next_multiplier
	production_costs_changed.emit(_production_cost_multiplier)


func get_selected_nest() -> Node2D:
	if selected_nest != null and not is_instance_valid(selected_nest):
		selected_nest = null
	return selected_nest


func get_spawned_monsters() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for child in spawned_monsters.get_children():
		if child is Node2D:
			result.append(child)
	return result


func select_nest_at(world_position: Vector2, require_visible := true) -> bool:
	_bind_dependencies()
	if mvp_map == null:
		clear_selection()
		return false
	var nearest_nest: Node2D
	var nearest_distance: float = INF
	for nest_value in mvp_map.call("get_active_nests"):
		var nest := nest_value as Node2D
		if nest == null or not is_instance_valid(nest):
			continue
		if require_visible and not nest.visible:
			continue
		var click_radius: float = _get_footprint_radius(nest) + 12.0
		var distance: float = nest.global_position.distance_to(world_position)
		if distance <= click_radius and distance < nearest_distance:
			nearest_nest = nest
			nearest_distance = distance
	if nearest_nest == null:
		clear_selection()
		return false
	return select_nest(nearest_nest)


func select_nest(nest: Node2D) -> bool:
	_bind_dependencies()
	if not _is_active_nest(nest):
		clear_selection()
		return false
	selected_nest = nest
	nest_selected.emit(nest)
	return true


func clear_selection() -> void:
	if selected_nest == null:
		return
	selected_nest = null
	selection_cleared.emit()


func produce(catalog_index: int) -> bool:
	_bind_dependencies()
	var nest := get_selected_nest()
	if not _is_active_nest(nest):
		clear_selection()
		production_failed.emit(&"no_nest_selected")
		return false
	if catalog_index < 0 or catalog_index >= production_catalog.size():
		production_failed.emit(&"invalid_configuration")
		return false
	var data := production_catalog[catalog_index] as MonsterProductionData
	if data == null or data.monster_scene == null or data.cost < 0:
		production_failed.emit(&"invalid_configuration")
		return false
	var effective_cost := get_effective_cost(catalog_index)
	if effective_cost < 0:
		production_failed.emit(&"invalid_configuration")
		return false
	if monster_economy == null or not monster_economy.can_afford(effective_cost):
		production_failed.emit(&"not_enough_dark_energy")
		return false

	var spawn_position := _find_spawn_position(nest)
	if not is_finite(spawn_position.x) or not is_finite(spawn_position.y):
		production_failed.emit(&"no_safe_spawn_position")
		return false
	var monster := data.monster_scene.instantiate() as Node2D
	if monster == null:
		production_failed.emit(&"invalid_configuration")
		return false
	if not monster_economy.try_spend(
		effective_cost, &"monster_production"
	):
		monster.queue_free()
		production_failed.emit(&"not_enough_dark_energy")
		return false

	_monster_serial += 1
	monster.name = "Produced_%03d_%s" % [_monster_serial, data.monster_id]
	monster.set_meta(&"monster_type_id", data.monster_id)
	monster.set_meta(&"production_nest_id", nest.get_instance_id())
	_configure_placeholder_visual(monster, data)
	spawned_monsters.add_child(monster)
	monster.global_position = spawn_position
	monster_produced.emit(monster, nest, data, effective_cost)
	return true


func _bind_dependencies() -> void:
	if monster_economy == null or not is_instance_valid(monster_economy):
		monster_economy = get_tree().get_first_node_in_group(
			&"monster_economy"
		) as MonsterEconomy
	if mvp_map == null or not is_instance_valid(mvp_map):
		mvp_map = get_tree().get_first_node_in_group(&"mvp_map")
		if mvp_map != null and not mvp_map.nest_destroyed.is_connected(
			_on_nest_destroyed
		):
			mvp_map.nest_destroyed.connect(_on_nest_destroyed)


func _on_nest_destroyed(nest: Node2D, _remaining_count: int) -> void:
	if selected_nest == nest:
		clear_selection()


func _is_active_nest(nest: Node2D) -> bool:
	if nest == null or not is_instance_valid(nest) or mvp_map == null:
		return false
	return nest in mvp_map.call("get_active_nests")


func _find_spawn_position(nest: Node2D) -> Vector2:
	var inward := nest.global_position.direction_to(battlefield_bounds.get_center())
	if inward.is_zero_approx():
		inward = Vector2.RIGHT
	var minimum_distance := (
		_get_footprint_radius(nest) + monster_radius + spawn_clearance
	)
	var angle_offsets := [
		0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0,
		120.0, -120.0, 150.0, -150.0, 180.0,
	]
	for ring_index in 3:
		var distance := minimum_distance + float(ring_index) * ring_spacing
		for angle_degrees in angle_offsets:
			var candidate := nest.global_position + inward.rotated(
				deg_to_rad(angle_degrees)
			) * distance
			if _is_spawn_position_clear(candidate):
				return candidate
	return Vector2(INF, INF)


func _is_spawn_position_clear(candidate: Vector2) -> bool:
	if not battlefield_bounds.grow(-monster_radius).has_point(candidate):
		return false
	for blocker in get_tree().get_nodes_in_group(&"placement_blockers"):
		if not blocker is Node2D or not is_instance_valid(blocker):
			continue
		var required_distance := (
			_get_footprint_radius(blocker) + monster_radius + spawn_clearance
		)
		if blocker.global_position.distance_to(candidate) < required_distance:
			return false
	for unit in get_tree().get_nodes_in_group(&"combat_units"):
		if not unit is Node2D or not is_instance_valid(unit):
			continue
		if unit.global_position.distance_to(candidate) < monster_radius * 2.0:
			return false
	return true


func _get_footprint_radius(building: Node) -> float:
	if building == null:
		return 0.0
	var footprint := building.get_node_or_null("BuildingFootprint")
	if footprint == null:
		return 0.0
	return float(footprint.get("radius"))


func _configure_placeholder_visual(
	monster: Node2D, data: MonsterProductionData
) -> void:
	var body := monster.get_node_or_null("Body") as Polygon2D
	if body != null:
		body.color = data.body_color
	var label := monster.get_node_or_null("Label") as Label
	if label != null:
		label.text = data.display_name.to_upper()
