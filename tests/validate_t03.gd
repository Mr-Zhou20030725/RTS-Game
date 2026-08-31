extends SceneTree

const HEALTH_COMPONENT_SCENE := preload("res://scenes/components/health_component.tscn")
const HEALTH_COMPONENT_SCRIPT := preload("res://scripts/components/health_component.gd")
const HUMAN_BASE_SCENE := preload("res://buildings/placeholders/human_base_placeholder.tscn")
const MONSTER_NEST_SCENE := preload("res://buildings/placeholders/monster_nest_placeholder.tscn")
const TEST_UNIT_SCENE := preload("res://units/placeholders/test_unit.tscn")

var death_event_count := 0


func _init() -> void:
	_run_validation()


func _run_validation() -> void:
	var component := HEALTH_COMPONENT_SCENE.instantiate()
	component.set("max_health", 100.0)
	component.connect("died", _on_component_died)
	root.add_child(component)
	await process_frame

	if not is_equal_approx(component.get("current_health"), 100.0):
		_fail("HealthComponent did not start at maximum health.")
		return

	var debug_bar := component.get_node("%DebugHealthBar") as ProgressBar
	if debug_bar == null or not is_equal_approx(debug_bar.value, 100.0):
		_fail("Debug health bar did not initialize correctly.")
		return

	var first_damage: float = component.call("take_damage", 30.0)
	if not is_equal_approx(first_damage, 30.0):
		_fail("HealthComponent reported an incorrect applied damage amount.")
		return
	if not is_equal_approx(component.get("current_health"), 70.0):
		_fail("Taking damage did not reduce current health.")
		return
	if not is_equal_approx(debug_bar.value, 70.0):
		_fail("Debug health bar did not follow current health.")
		return

	var applied_healing: float = component.call("heal", 10.0)
	if not is_equal_approx(applied_healing, 10.0):
		_fail("Healing did not report the applied amount.")
		return
	if not is_equal_approx(component.get("current_health"), 80.0):
		_fail("Healing did not restore current health.")
		return

	component.call("take_damage", 200.0)
	if not component.get("is_dead"):
		_fail("HealthComponent did not enter the dead state at zero health.")
		return
	if not is_zero_approx(component.get("current_health")):
		_fail("Fatal damage did not clamp health to zero.")
		return
	if death_event_count != 1:
		_fail("Death signal did not fire exactly once on fatal damage.")
		return

	component.call("take_damage", 10.0)
	component.call("heal", 10.0)
	if death_event_count != 1:
		_fail("Repeated damage triggered death more than once.")
		return
	if not is_zero_approx(component.get("current_health")):
		_fail("A dead HealthComponent changed health.")
		return

	root.remove_child(component)
	component.queue_free()
	await process_frame

	var actor_scenes: Array[PackedScene] = [
		HUMAN_BASE_SCENE,
		MONSTER_NEST_SCENE,
		TEST_UNIT_SCENE,
	]
	var expected_max_health := [1000.0, 600.0, 100.0]

	for actor_index in actor_scenes.size():
		var actor := actor_scenes[actor_index].instantiate()
		root.add_child(actor)
		await process_frame

		var actor_health := actor.get_node_or_null("HealthComponent")
		if actor_health == null:
			_fail("%s does not contain HealthComponent." % actor.name)
			return
		if actor_health.get_script() != HEALTH_COMPONENT_SCRIPT:
			_fail("%s is not using the shared HealthComponent script." % actor.name)
			return
		if not is_equal_approx(
			actor_health.get("max_health"), expected_max_health[actor_index]
		):
			_fail("%s has an unexpected maximum health." % actor.name)
			return

		actor_health.call("take_damage", 1.0)
		if not is_equal_approx(
			actor_health.get("current_health"),
			expected_max_health[actor_index] - 1.0
		):
			_fail("%s could not take damage through HealthComponent." % actor.name)
			return

		root.remove_child(actor)
		actor.queue_free()
		await process_frame

	print(
		"T03 validation passed: damage, healing, one-shot death, debug bar, "
		+ "and shared base/nest/unit component."
	)
	quit()


func _on_component_died(_source: Node) -> void:
	death_event_count += 1


func _fail(message: String) -> void:
	push_error("T03 validation failed: %s" % message)
	quit(1)
