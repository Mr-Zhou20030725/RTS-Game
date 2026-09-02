class_name NestStrengtheningData
extends Resource

## Data-only definition for one surviving-nest stage.

@export_range(1, 4, 1) var active_nest_count := 4
@export var stage_id: StringName = &"normal"
@export var display_name := "Normal Nests"
@export_range(1.0, 10.0, 0.05) var max_health_multiplier := 1.0
@export_range(0.0, 10.0, 0.05) var energy_per_nest_multiplier := 1.0
@export_range(0.1, 1.0, 0.05) var production_cost_multiplier := 1.0
@export var outer_color := Color(0.298, 0.086, 0.125, 1.0)
@export var core_color := Color(0.682, 0.173, 0.231, 1.0)
@export var label_text := "NEST"
