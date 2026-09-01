class_name MonsterProductionData
extends Resource

## Minimal T18 definition for a monster that can be produced by a nest.
## T20 can extend these data assets with the six final monster stat blocks.

@export var monster_id: StringName = &"grunt"
@export var display_name := "Grunt"
@export_range(0, 1000000, 1) var cost := 20
@export var monster_scene: PackedScene
@export var body_color := Color(0.72, 0.21, 0.25, 1.0)
