class_name FogOfWarManager
extends Node

## Human real-time fog: vision outside active sources returns to darkness.

signal revealable_visibility_changed(target: Node2D, is_visible: bool)

@export var human_fog_enabled := true
@export_range(0.02, 1.0, 0.01) var visibility_update_interval := 0.08
@export var hidden_ambient_color := Color(0.025, 0.035, 0.055, 1.0)

@onready var canvas_modulate: CanvasModulate = %FogCanvasModulate

var _update_elapsed := 0.0
var _visibility_cache: Dictionary[int, bool] = {}


func _ready() -> void:
	add_to_group(&"human_fog_manager")
	canvas_modulate.color = hidden_ambient_color
	canvas_modulate.visible = human_fog_enabled
	call_deferred("refresh_visibility")


func _process(delta: float) -> void:
	if not human_fog_enabled:
		return
	_update_elapsed += delta
	if _update_elapsed < visibility_update_interval:
		return
	_update_elapsed = 0.0
	refresh_visibility()


func set_human_fog_enabled(value: bool) -> void:
	human_fog_enabled = value
	if is_node_ready():
		canvas_modulate.visible = value
	refresh_visibility()


func is_human_fog_enabled() -> bool:
	return human_fog_enabled


func is_position_visible_to_human(
	world_position: Vector2, margin: float = 0.0
) -> bool:
	if not human_fog_enabled:
		return true
	for source_node in get_tree().get_nodes_in_group(&"human_vision_sources"):
		if not source_node is VisionSourceComponent:
			continue
		var source := source_node as VisionSourceComponent
		if not source.is_vision_active():
			continue
		if source.global_position.distance_to(world_position) <= (
			source.get_vision_radius() + maxf(margin, 0.0)
		):
			return true
	return false


func is_node_visible_to_human(target: Node2D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var faction := FactionComponent.find_on(target)
	if faction != null and faction.faction == FactionComponent.Faction.HUMAN:
		return true
	return is_position_visible_to_human(target.global_position)


func get_active_vision_source_count() -> int:
	var count := 0
	for source_node in get_tree().get_nodes_in_group(&"human_vision_sources"):
		if (
			source_node is VisionSourceComponent
			and (source_node as VisionSourceComponent).is_vision_active()
		):
			count += 1
	return count


func refresh_visibility() -> void:
	if not is_inside_tree():
		return
	for nest_node in get_tree().get_nodes_in_group(&"monster_nest_placeholder"):
		if nest_node is Node2D:
			_apply_revealable_visibility(nest_node as Node2D)
	for unit_node in get_tree().get_nodes_in_group(&"combat_units"):
		if not unit_node is Node2D:
			continue
		var unit := unit_node as Node2D
		var faction := FactionComponent.find_on(unit)
		if faction != null and faction.faction == FactionComponent.Faction.MONSTER:
			_apply_revealable_visibility(unit)
	for projectile_node in get_tree().get_nodes_in_group(&"combat_projectiles"):
		if projectile_node is Node2D:
			_set_canvas_item_visible(
				projectile_node as Node2D,
				not human_fog_enabled
				or is_position_visible_to_human(projectile_node.global_position)
			)


func _apply_revealable_visibility(target: Node2D) -> void:
	var should_be_visible := (
		not human_fog_enabled or is_node_visible_to_human(target)
	)
	_set_canvas_item_visible(target, should_be_visible)
	var target_id := target.get_instance_id()
	if _visibility_cache.get(target_id, not should_be_visible) != should_be_visible:
		revealable_visibility_changed.emit(target, should_be_visible)
	_visibility_cache[target_id] = should_be_visible


func _set_canvas_item_visible(item: CanvasItem, value: bool) -> void:
	item.visible = value
