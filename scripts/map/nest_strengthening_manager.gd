class_name NestStrengtheningManager
extends Node

## Applies a data-driven comeback stage whenever an active nest is destroyed.

signal stage_changed(profile: NestStrengtheningData, active_nests: int)

@export var stage_profiles: Array[Resource] = []

var current_profile: NestStrengtheningData
var mvp_map: Node
var monster_economy: MonsterEconomy
var monster_production_manager: MonsterProductionManager


func _ready() -> void:
	call_deferred("_bind_dependencies_and_apply")


func get_current_profile() -> NestStrengtheningData:
	return current_profile


func get_stage_for_nest_count(active_nest_count: int) -> NestStrengtheningData:
	for profile_resource in stage_profiles:
		var profile := profile_resource as NestStrengtheningData
		if profile != null and profile.active_nest_count == active_nest_count:
			return profile
	return null


func refresh_stage() -> void:
	if mvp_map == null or not is_instance_valid(mvp_map):
		_bind_dependencies_and_apply()
		return
	_apply_stage(int(mvp_map.call("get_active_nest_count")))


func _bind_dependencies_and_apply() -> void:
	mvp_map = get_tree().get_first_node_in_group(&"mvp_map")
	monster_economy = get_tree().get_first_node_in_group(
		&"monster_economy"
	) as MonsterEconomy
	monster_production_manager = get_tree().get_first_node_in_group(
		&"monster_production_manager"
	) as MonsterProductionManager
	if mvp_map == null:
		push_error("NestStrengtheningManager requires MVPMap.")
		return
	if not mvp_map.active_nest_count_changed.is_connected(
		_on_active_nest_count_changed
	):
		mvp_map.active_nest_count_changed.connect(
			_on_active_nest_count_changed
		)
	_apply_stage(int(mvp_map.call("get_active_nest_count")))


func _on_active_nest_count_changed(active_nest_count: int) -> void:
	_apply_stage(active_nest_count)


func _apply_stage(active_nest_count: int) -> void:
	if active_nest_count <= 0:
		current_profile = null
		return
	var profile := get_stage_for_nest_count(active_nest_count)
	if profile == null:
		push_error(
			"No nest strengthening profile for %d active nests."
			% active_nest_count
		)
		return
	current_profile = profile
	for nest_value in mvp_map.call("get_active_nests"):
		var nest := nest_value as Node2D
		if nest != null and is_instance_valid(nest):
			_apply_profile_to_nest(nest, profile)
	if monster_economy != null:
		monster_economy.set_nest_income_multiplier(
			profile.energy_per_nest_multiplier
		)
	if monster_production_manager != null:
		monster_production_manager.set_production_cost_multiplier(
			profile.production_cost_multiplier
		)
	stage_changed.emit(profile, active_nest_count)


func _apply_profile_to_nest(
	nest: Node2D, profile: NestStrengtheningData
) -> void:
	var health := nest.get_node_or_null("HealthComponent") as HealthComponent
	if health != null:
		if not nest.has_meta(&"base_nest_max_health"):
			nest.set_meta(&"base_nest_max_health", health.max_health)
		var base_health := float(nest.get_meta(&"base_nest_max_health"))
		health.set_max_health(
			base_health * profile.max_health_multiplier, true
		)
	var outer_ground := nest.get_node_or_null("OuterGround") as Polygon2D
	if outer_ground != null:
		outer_ground.color = profile.outer_color
	var core := nest.get_node_or_null("Core") as Polygon2D
	if core != null:
		core.color = profile.core_color
	var label := nest.get_node_or_null("Label") as Label
	if label != null:
		label.text = profile.label_text
		label.add_theme_font_size_override(
			"font_size", 10 if _is_mother_profile(profile) else 13
		)
	nest.set_meta(&"nest_strength_stage", profile.stage_id)
	nest.set_meta(
		&"nest_health_multiplier", profile.max_health_multiplier
	)


func _is_mother_profile(profile: NestStrengtheningData) -> bool:
	return profile.active_nest_count == 1
