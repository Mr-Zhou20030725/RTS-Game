class_name MonsterProductionData
extends Resource

## Complete data-only definition shared by all six T20 monster roles.

enum AttackStyle {
	MELEE,
	RANGED,
}

enum SpecialAbility {
	NONE,
	SHORT_STEALTH,
	SUPPORT_AURA,
}

@export var monster_id: StringName = &"goblin"
@export var display_name := "Goblin"
@export var role_description := "Cheap expendable melee unit"
@export_range(0, 1000000, 1) var cost := 15
@export var monster_scene: PackedScene
@export_range(1.0, 1000000.0, 1.0) var max_health := 70.0
@export_range(1.0, 1000.0, 1.0) var move_speed := 145.0
@export_range(8.0, 64.0, 1.0) var collision_radius := 15.0
@export_range(0.5, 2.0, 0.05) var visual_scale := 0.8
@export var attack_style: AttackStyle = AttackStyle.MELEE
@export_range(0.1, 100000.0, 0.1) var damage := 10.0
@export_range(0.05, 60.0, 0.05) var attack_interval := 0.55
@export_range(1.0, 2000.0, 1.0) var attack_range := 36.0
@export_range(1.0, 3000.0, 1.0) var acquisition_range := 230.0
@export_range(1.0, 4000.0, 1.0) var chase_range := 360.0
@export_range(1.0, 5000.0, 1.0) var projectile_speed := 500.0
@export_enum("Nearest", "Units First", "Buildings First") var target_priority := 0
@export var special_ability: SpecialAbility = SpecialAbility.NONE
@export_range(0.0, 30.0, 0.1) var stealth_duration := 0.0
@export_range(0.0, 1000.0, 1.0) var aura_radius := 0.0
@export_range(1.0, 3.0, 0.05) var aura_damage_multiplier := 1.0
@export_range(1.0, 3.0, 0.05) var aura_speed_multiplier := 1.0
@export var body_color := Color(0.38, 0.7, 0.25, 1.0)
@export var accent_color := Color(0.75, 0.95, 0.45, 1.0)
@export var projectile_color := Color.WHITE
