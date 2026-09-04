class_name DefenseTower
extends Node2D

## One tower implementation configured entirely by TowerData.

signal upgraded(tower: DefenseTower)

@export var tower_data: TowerData

@onready var foundation: Polygon2D = %Foundation
@onready var turret: Polygon2D = %Turret
@onready var tower_label: Label = %TowerLabel
@onready var selection_indicator: Line2D = %SelectionIndicator
@onready var health_component: HealthComponent = $HealthComponent
@onready var ranged_component := $RangedAttackComponent
@onready var vision_source: VisionSourceComponent = $VisionSourceComponent

var _is_preview := false
var _is_upgraded := false
var _is_selected := false
var _event_combat_modifiers: Dictionary = {}


func _ready() -> void:
	_apply_tower_data()
	health_component.died.connect(_on_died)
	_apply_preview_state()


func configure_tower(data: TowerData) -> void:
	tower_data = data
	if is_node_ready():
		_apply_tower_data()


func set_build_preview(value: bool) -> void:
	_is_preview = value
	if is_node_ready():
		_apply_preview_state()


func get_tower_data() -> TowerData:
	return tower_data


func can_upgrade() -> bool:
	return (
		tower_data != null
		and not _is_preview
		and not _is_upgraded
		and not health_component.is_dead
	)


func get_upgrade_cost() -> int:
	return 0 if tower_data == null else tower_data.upgrade_cost


func is_upgraded() -> bool:
	return _is_upgraded


func apply_upgrade() -> bool:
	if not can_upgrade():
		return false
	_is_upgraded = true
	_apply_combat_stats()
	turret.scale = Vector2(1.18, 1.18)
	tower_label.text = "%s II" % tower_data.display_name.to_upper()
	upgraded.emit(self)
	return true


func set_selected(value: bool) -> void:
	_is_selected = value and not _is_preview and not health_component.is_dead
	selection_indicator.visible = _is_selected


func set_event_combat_modifier(
	effect_id: StringName,
	damage_multiplier: float,
	interval_multiplier: float,
	range_multiplier: float
) -> void:
	_event_combat_modifiers[effect_id] = Vector3(
		maxf(damage_multiplier, 0.01),
		maxf(interval_multiplier, 0.01),
		maxf(range_multiplier, 0.01)
	)
	_apply_combat_stats()


func remove_event_combat_modifier(effect_id: StringName) -> void:
	if _event_combat_modifiers.erase(effect_id):
		_apply_combat_stats()


func _apply_tower_data() -> void:
	if tower_data == null:
		return
	health_component.max_health = tower_data.max_health
	health_component.current_health = tower_data.max_health
	foundation.color = tower_data.foundation_color
	turret.color = tower_data.tower_color
	tower_label.text = tower_data.display_name.to_upper()
	_apply_combat_stats()


func _apply_combat_stats() -> void:
	if tower_data == null:
		return
	ranged_component.attack_damage = tower_data.damage
	ranged_component.attack_interval = tower_data.attack_interval
	ranged_component.attack_range = tower_data.attack_range
	ranged_component.projectile_speed = tower_data.projectile_speed
	ranged_component.splash_radius = tower_data.splash_radius
	ranged_component.slow_multiplier = tower_data.slow_multiplier
	ranged_component.slow_duration = tower_data.slow_duration
	ranged_component.projectile_modulate = tower_data.projectile_color
	vision_source.set_vision_radius(tower_data.vision_radius)
	if _is_upgraded:
		ranged_component.attack_damage *= tower_data.upgrade_damage_multiplier
		ranged_component.attack_range += tower_data.upgrade_range_bonus
		ranged_component.attack_interval *= (
			tower_data.upgrade_attack_interval_multiplier
		)
	for modifier_value in _event_combat_modifiers.values():
		var modifier := modifier_value as Vector3
		ranged_component.attack_damage *= modifier.x
		ranged_component.attack_interval *= modifier.y
		ranged_component.attack_range *= modifier.z


func _apply_preview_state() -> void:
	ranged_component.combat_enabled = not _is_preview
	vision_source.enabled = not _is_preview
	if _is_preview:
		set_selected(false)
	if _is_preview:
		if is_in_group(&"combat_targets"):
			remove_from_group(&"combat_targets")
	else:
		if not is_in_group(&"combat_targets"):
			add_to_group(&"combat_targets")


func _on_died(_source: Node) -> void:
	ranged_component.combat_enabled = false
	set_selected(false)
	for group_name in [&"combat_targets", &"placement_blockers", &"placed_towers"]:
		if is_in_group(group_name):
			remove_from_group(group_name)
	modulate = Color(0.35, 0.35, 0.35, 0.65)
