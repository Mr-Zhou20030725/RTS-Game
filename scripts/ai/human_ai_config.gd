class_name HumanAIConfig
extends Resource

## Tunable pacing, spending, and decision thresholds for Human AI v1.

@export_range(0.2, 60.0, 0.1) var analysis_interval := 2.0
@export_range(0.5, 120.0, 0.5) var build_interval := 7.0
@export_range(0.5, 120.0, 0.5) var recruit_interval := 10.0
@export_range(1.0, 180.0, 0.5) var expedition_interval := 12.0
@export_range(0.0, 1200.0, 1.0) var midgame_start_time := 75.0
@export_range(0, 10000, 1) var gold_reserve := 70
@export_range(1, 40, 1) var maximum_towers := 14
@export_range(1, 20, 1) var maximum_squads := 7
@export_range(1, 20, 1) var minimum_defense_towers := 3
@export_range(1, 30, 1) var minimum_expedition_members := 6
@export_range(80.0, 800.0, 10.0) var threat_scan_radius := 520.0
@export_range(0.0, 100.0, 0.1) var threat_response_threshold := 8.0
@export_range(80.0, 400.0, 5.0) var inner_tower_radius := 175.0
@export_range(80.0, 500.0, 5.0) var outer_tower_radius := 245.0
@export_range(100.0, 900.0, 10.0) var exploration_radius := 500.0
@export var tower_rotation := PackedInt32Array([0, 2, 1, 0, 3, 4])
@export var squad_rotation := PackedInt32Array([0, 1, 0, 2, 3])
@export_range(1, 32, 1) var maximum_catch_up_cycles := 8
