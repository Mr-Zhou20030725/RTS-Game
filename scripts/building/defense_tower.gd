class_name DefenseTower
extends Node2D

## One tower implementation configured entirely by TowerData.

@export var tower_data: TowerData

@onready var foundation: Polygon2D = %Foundation
@onready var turret: Polygon2D = %Turret
@onready var tower_label: Label = %TowerLabel
@onready var health_component: HealthComponent = $HealthComponent
@onready var ranged_component := $RangedAttackComponent

var _is_preview := false


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


func _apply_tower_data() -> void:
	if tower_data == null:
		return
	health_component.max_health = tower_data.max_health
	health_component.current_health = tower_data.max_health
	foundation.color = tower_data.foundation_color
	turret.color = tower_data.tower_color
	tower_label.text = tower_data.display_name.to_upper()
	ranged_component.attack_damage = tower_data.damage
	ranged_component.attack_interval = tower_data.attack_interval
	ranged_component.attack_range = tower_data.attack_range
	ranged_component.projectile_speed = tower_data.projectile_speed
	ranged_component.splash_radius = tower_data.splash_radius
	ranged_component.slow_multiplier = tower_data.slow_multiplier
	ranged_component.slow_duration = tower_data.slow_duration
	ranged_component.projectile_modulate = tower_data.projectile_color


func _apply_preview_state() -> void:
	ranged_component.combat_enabled = not _is_preview
	if _is_preview:
		if is_in_group(&"combat_targets"):
			remove_from_group(&"combat_targets")
	else:
		if not is_in_group(&"combat_targets"):
			add_to_group(&"combat_targets")


func _on_died(_source: Node) -> void:
	ranged_component.combat_enabled = false
	for group_name in [&"combat_targets", &"placement_blockers", &"placed_towers"]:
		if is_in_group(group_name):
			remove_from_group(group_name)
	modulate = Color(0.35, 0.35, 0.35, 0.65)
