class_name TowerData
extends Resource

## Data-only definition shared by every buildable tower.

enum AttackStyle {
	SINGLE_TARGET,
	SPLASH,
	SLOW,
}

@export var tower_id: StringName = &"arrow"
@export var display_name := "Arrow Tower"
@export_range(0, 1000000, 1) var cost := 50
@export_range(1.0, 1000000.0, 1.0) var max_health := 250.0
@export var attack_style: AttackStyle = AttackStyle.SINGLE_TARGET
@export_range(0.1, 100000.0, 0.1) var damage := 18.0
@export_range(0.05, 60.0, 0.05) var attack_interval := 0.55
@export_range(1.0, 2000.0, 1.0) var attack_range := 300.0
@export_range(1.0, 5000.0, 1.0) var projectile_speed := 520.0
@export_range(16.0, 2000.0, 1.0) var vision_radius := 220.0
@export_range(0.0, 1000.0, 1.0) var splash_radius := 0.0
@export_range(0.1, 1.0, 0.05) var slow_multiplier := 1.0
@export_range(0.0, 60.0, 0.1) var slow_duration := 0.0
@export_group("Level 2 Upgrade")
@export_range(0, 1000000, 1) var upgrade_cost := 75
@export_range(1.0, 10.0, 0.05) var upgrade_damage_multiplier := 1.0
@export_range(0.0, 2000.0, 1.0) var upgrade_range_bonus := 0.0
@export_range(0.1, 1.0, 0.05) var upgrade_attack_interval_multiplier := 1.0
@export var upgrade_description := "Damage upgrade"
@export_group("")
@export var foundation_color := Color(0.18, 0.36, 0.47, 1.0)
@export var tower_color := Color(0.36, 0.70, 0.81, 1.0)
@export var projectile_color := Color(1.0, 0.82, 0.27, 1.0)
