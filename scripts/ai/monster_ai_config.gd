class_name MonsterAIConfig
extends Resource

## Tunable rule weights and pacing for Monster AI v1.

@export_range(0.2, 60.0, 0.1) var production_interval := 3.5
@export_range(1.0, 120.0, 0.5) var attack_interval := 12.0
@export_range(1, 30, 1) var minimum_wave_size := 4
@export_range(1, 50, 1) var maximum_wave_size := 10
@export_range(4, 200, 1) var maximum_ai_monsters := 48
@export var production_rotation := PackedInt32Array([0, 0, 1, 3, 2, 5])
@export_range(80.0, 600.0, 10.0) var staging_distance := 300.0
@export_range(0.0, 100.0, 0.1) var base_unit_strength := 8.0
@export_range(0.0, 10.0, 0.01) var health_strength_weight := 0.04
@export_range(0.0, 10.0, 0.01) var damage_per_second_weight := 0.4
@export_range(0.0, 2.0, 0.001) var range_strength_weight := 0.01
@export_range(0.0, 200.0, 1.0) var recent_direction_pressure := 30.0
@export_range(0.0, 1.0, 0.01) var pressure_decay := 0.55
@export_range(1, 32, 1) var maximum_catch_up_cycles := 8
