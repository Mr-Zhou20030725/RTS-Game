extends Node2D

## Builds the fixed MVP map layout and chooses active nest spawn points.

signal layout_generated(selected_candidates: Array[StringName])

@export var human_base_scene: PackedScene
@export var monster_nest_scene: PackedScene
@export_range(1, 8, 1) var active_nest_count := 4
@export var minimum_nest_separation := 240.0
@export var minimum_base_distance := 350.0
@export var generation_seed: int = 0

@onready var human_base_spawn: Marker2D = %HumanBaseSpawn
@onready var nest_candidates: Node2D = %NestCandidates
@onready var spawned_buildings: Node2D = %SpawnedBuildings

var human_base: Node2D
var active_nests: Array[Node2D] = []
var selected_candidate_names: Array[StringName] = []


func _ready() -> void:
	generate_layout()


func generate_layout() -> void:
	_clear_spawned_buildings()
	_spawn_human_base()

	var candidates := _get_nest_candidates()
	if candidates.size() < active_nest_count:
		push_error(
			"MVP map needs at least %d valid nest candidates, but only %d exist."
			% [active_nest_count, candidates.size()]
		)
		return

	var random := RandomNumberGenerator.new()
	if generation_seed == 0:
		random.randomize()
	else:
		random.seed = generation_seed
	_shuffle_candidates(candidates, random)

	var selected: Array[Marker2D] = []
	for candidate in candidates:
		if _is_valid_candidate(candidate, selected):
			selected.append(candidate)
		if selected.size() == active_nest_count:
			break

	if selected.size() != active_nest_count:
		push_error(
			"Unable to place %d nests with the configured distance constraints."
			% active_nest_count
		)
		return

	for candidate in selected:
		_spawn_monster_nest(candidate)

	layout_generated.emit(selected_candidate_names.duplicate())


func get_active_nests() -> Array[Node2D]:
	return active_nests.duplicate()


func get_selected_candidate_names() -> Array[StringName]:
	return selected_candidate_names.duplicate()


func get_nest_candidate_count() -> int:
	return _get_nest_candidates().size()


func _spawn_human_base() -> void:
	if human_base_scene == null:
		push_error("Human base placeholder scene is not configured.")
		return

	human_base = human_base_scene.instantiate() as Node2D
	spawned_buildings.add_child(human_base)
	human_base.position = spawned_buildings.to_local(human_base_spawn.global_position)


func _spawn_monster_nest(candidate: Marker2D) -> void:
	if monster_nest_scene == null:
		push_error("Monster nest placeholder scene is not configured.")
		return

	var nest := monster_nest_scene.instantiate() as Node2D
	nest.name = "MonsterNest_%s" % candidate.name
	spawned_buildings.add_child(nest)
	nest.position = spawned_buildings.to_local(candidate.global_position)
	active_nests.append(nest)
	selected_candidate_names.append(candidate.name)


func _clear_spawned_buildings() -> void:
	human_base = null
	active_nests.clear()
	selected_candidate_names.clear()
	for child in spawned_buildings.get_children():
		spawned_buildings.remove_child(child)
		child.queue_free()


func _get_nest_candidates() -> Array[Marker2D]:
	var candidates: Array[Marker2D] = []
	for child in nest_candidates.get_children():
		if child is Marker2D:
			candidates.append(child)
	return candidates


func _shuffle_candidates(
	candidates: Array[Marker2D], random: RandomNumberGenerator
) -> void:
	for index in range(candidates.size() - 1, 0, -1):
		var swap_index := random.randi_range(0, index)
		var temporary := candidates[index]
		candidates[index] = candidates[swap_index]
		candidates[swap_index] = temporary


func _is_valid_candidate(
	candidate: Marker2D, selected: Array[Marker2D]
) -> bool:
	if candidate.global_position.distance_to(human_base_spawn.global_position) < minimum_base_distance:
		return false

	for existing in selected:
		if candidate.global_position.distance_to(existing.global_position) < minimum_nest_separation:
			return false
	return true
