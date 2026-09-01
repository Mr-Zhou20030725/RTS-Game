class_name HumanSquadData
extends Resource

## Data-only definition for a recruitable Human squad and all of its members.

enum AttackStyle {
	MELEE,
	RANGED,
	SPLASH_RANGED,
}

@export var squad_id: StringName = &"swordsman"
@export var display_name := "Swordsman Squad"
@export_range(0, 1000000, 1) var cost := 60
@export_range(2, 12, 1) var member_count := 4
@export_range(24.0, 128.0, 1.0) var formation_spacing := 42.0
@export_range(1.0, 1000000.0, 1.0) var max_health := 140.0
@export_range(1.0, 1000.0, 1.0) var move_speed := 125.0
@export_range(16.0, 2000.0, 1.0) var vision_radius := 155.0
@export var attack_style: AttackStyle = AttackStyle.MELEE
@export_range(0.1, 100000.0, 0.1) var damage := 24.0
@export_range(0.05, 60.0, 0.05) var attack_interval := 0.65
@export_range(1.0, 2000.0, 1.0) var attack_range := 42.0
@export_range(1.0, 3000.0, 1.0) var acquisition_range := 280.0
@export_range(1.0, 4000.0, 1.0) var chase_range := 420.0
@export_range(1.0, 5000.0, 1.0) var projectile_speed := 500.0
@export_range(0.0, 1000.0, 1.0) var splash_radius := 0.0
@export var body_color := Color(0.31, 0.65, 0.79, 1.0)
@export var accent_color := Color(0.85, 0.68, 0.32, 1.0)
