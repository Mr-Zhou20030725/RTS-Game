extends SceneTree

const MAP_SCENE := preload("res://scenes/map/mvp_map.tscn")
const EXPECTED_BASE_POSITION := Vector2(2000.0, 2000.0)
const EXPECTED_NEST_COUNT := 4
const MINIMUM_CANDIDATE_COUNT := 8
const MINIMUM_BASE_DISTANCE := 1500.0
const MINIMUM_NEST_SEPARATION := 500.0


func _init() -> void:
	_run_validation()


func _run_validation() -> void:
	var combinations: Dictionary = {}
	var generated_directions: Dictionary = {}

	for test_seed in range(1, 21):
		var map := MAP_SCENE.instantiate()
		map.set("generation_seed", test_seed)
		root.add_child(map)
		await process_frame

		if map.call("get_nest_candidate_count") < MINIMUM_CANDIDATE_COUNT:
			_fail("Map has fewer than 8 nest candidates.")
			return
		var ground := map.get_node("Ground") as Polygon2D
		if (
			ground.polygon.size() != 4
			or ground.polygon[0] != Vector2.ZERO
			or ground.polygon[2] != Vector2(4000.0, 4000.0)
		):
			_fail("The playable map is not exactly 4000 by 4000.")
			return

		var human_base := map.get("human_base") as Node2D
		if human_base == null:
			_fail("Human base placeholder was not spawned.")
			return
		if human_base.global_position.distance_to(EXPECTED_BASE_POSITION) > 0.1:
			_fail("Human base is not at the expected central position.")
			return

		var active_nests: Array = map.call("get_active_nests")
		if active_nests.size() != EXPECTED_NEST_COUNT:
			_fail("A generated layout did not contain exactly 4 nests.")
			return

		for nest_index in active_nests.size():
			var nest := active_nests[nest_index] as Node2D
			if nest.global_position.distance_to(human_base.global_position) < MINIMUM_BASE_DISTANCE:
				_fail("A nest spawned too close to the human base.")
				return
			for other_index in range(nest_index + 1, active_nests.size()):
				var other_nest := active_nests[other_index] as Node2D
				if nest.global_position.distance_to(other_nest.global_position) < MINIMUM_NEST_SEPARATION:
					_fail("Two nests spawned too close together.")
					return

		var selected_names: Array = map.call("get_selected_candidate_names")
		for candidate_name in selected_names:
			var direction := _get_candidate_direction(String(candidate_name))
			if direction.is_empty():
				_fail("A nest candidate has no cardinal direction.")
				return
			generated_directions[direction] = true
		selected_names.sort()
		combinations["|".join(selected_names)] = true

		root.remove_child(map)
		map.queue_free()
		await process_frame

	if combinations.size() < 4:
		_fail("Generated layouts did not produce enough varied nest combinations.")
		return

	if generated_directions.size() != 4:
		_fail("Generated nests did not cover north, east, south, and west.")
		return

	print(
		"T02 validation passed: 8 candidates cover N/E/S/W, 4 safe nests, "
		+ "%d combinations across 20 seeded runs." % combinations.size()
	)
	quit()


func _get_candidate_direction(candidate_name: String) -> String:
	for direction in ["North", "East", "South", "West"]:
		if candidate_name.begins_with(direction):
			return direction
	return ""


func _fail(message: String) -> void:
	push_error("T02 validation failed: %s" % message)
	quit(1)
