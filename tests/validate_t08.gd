extends SceneTree

const TargetSelector := preload("res://scripts/combat/targeting_service.gd")
const HUMAN_SCENE := preload("res://units/placeholders/test_unit.tscn")
const ARCHER_SCENE := preload("res://units/placeholders/test_archer.tscn")
const MONSTER_SCENE := preload("res://units/placeholders/test_monster.tscn")
const NEST_SCENE := preload(
	"res://buildings/placeholders/monster_nest_placeholder.tscn"
)

var target_history: Array[Node2D] = []


func _init() -> void:
	_run_validation()


func _run_validation() -> void:
	if not await _validate_nearest_legal_target_and_priority_modes():
		return
	if not await _validate_automatic_retarget_without_idle():
		return

	print(
		"T08 validation passed: nearest legal targeting, unit/building "
		+ "priority extension points, and automatic invalid-target recovery."
	)
	quit()


func _validate_nearest_legal_target_and_priority_modes() -> bool:
	var human := HUMAN_SCENE.instantiate()
	var friendly := HUMAN_SCENE.instantiate()
	var near_monster := MONSTER_SCENE.instantiate()
	var far_monster := MONSTER_SCENE.instantiate()
	var near_nest := NEST_SCENE.instantiate()

	human.position = Vector2(100, 200)
	friendly.position = Vector2(110, 200)
	near_monster.position = Vector2(180, 200)
	far_monster.position = Vector2(320, 200)
	near_nest.position = Vector2(140, 200)

	_set_combat_enabled(human, false)
	_set_combat_enabled(friendly, false)
	_set_combat_enabled(near_monster, false)
	_set_combat_enabled(far_monster, false)
	for actor in [human, friendly, near_monster, far_monster, near_nest]:
		root.add_child(actor)
	await process_frame

	var nearest_unit: Node2D = TargetSelector.find_best_target(
		human,
		[friendly, far_monster, near_monster],
		500.0,
		TargetSelector.PriorityMode.NEAREST
	)
	if nearest_unit != near_monster:
		_fail("Default targeting did not choose the nearest legal enemy unit.")
		return false

	var nearest_any: Node2D = TargetSelector.find_best_target(
		human,
		[far_monster, near_nest],
		500.0,
		TargetSelector.PriorityMode.NEAREST
	)
	if nearest_any != near_nest:
		_fail("Nearest mode did not rank targets strictly by distance.")
		return false

	var preferred_unit: Node2D = TargetSelector.find_best_target(
		human,
		[far_monster, near_nest],
		500.0,
		TargetSelector.PriorityMode.UNITS_FIRST
	)
	if preferred_unit != far_monster:
		_fail("Units-first extension did not prefer a legal unit.")
		return false

	var preferred_building: Node2D = TargetSelector.find_best_target(
		human,
		[far_monster, near_nest],
		500.0,
		TargetSelector.PriorityMode.BUILDINGS_FIRST
	)
	if preferred_building != near_nest:
		_fail("Buildings-first extension did not prefer a legal building.")
		return false

	CombatRules.try_apply_damage(human, near_monster, 100000.0)
	var replacement: Node2D = TargetSelector.find_best_target(
		human,
		[friendly, near_monster, far_monster],
		500.0,
		TargetSelector.PriorityMode.NEAREST
	)
	if replacement != far_monster:
		_fail("Dead target was not rejected in favor of a surviving enemy.")
		return false
	if TargetSelector.find_best_target(
		human,
		[far_monster],
		100.0,
		TargetSelector.PriorityMode.NEAREST
	) != null:
		_fail("Target outside the configured search range was accepted.")
		return false

	_remove_actors([human, friendly, near_monster, far_monster, near_nest])
	await process_frame
	return true


func _validate_automatic_retarget_without_idle() -> bool:
	target_history.clear()
	var archer := ARCHER_SCENE.instantiate()
	var first_monster := MONSTER_SCENE.instantiate()
	var second_monster := MONSTER_SCENE.instantiate()
	archer.position = Vector2(200, 460)
	first_monster.position = Vector2(330, 460)
	second_monster.position = Vector2(440, 460)

	var ranged = archer.get_node("RangedAttackComponent")
	ranged.attack_damage = 100.0
	ranged.attack_interval = 0.05
	ranged.attack_range = 400.0
	ranged.projectile_speed = 5000.0
	ranged.target_priority = TargetSelector.PriorityMode.NEAREST
	ranged.target_changed.connect(_on_target_changed)
	for monster in [first_monster, second_monster]:
		_set_combat_enabled(monster, false)
		(monster.get_node("HealthComponent") as HealthComponent).max_health = 50.0

	root.add_child(archer)
	root.add_child(first_monster)
	root.add_child(second_monster)
	for _frame in 180:
		await physics_frame
		if (
			(first_monster.get_node("HealthComponent") as HealthComponent).is_dead
			and (second_monster.get_node("HealthComponent") as HealthComponent).is_dead
		):
			break

	if target_history.is_empty() or target_history[0] != first_monster:
		_fail("Ranged unit did not initially choose the closest enemy.")
		return false
	if not target_history.has(second_monster):
		_fail("Ranged unit did not reacquire the surviving nearby enemy.")
		return false
	if not (first_monster.get_node("HealthComponent") as HealthComponent).is_dead:
		_fail("First target was not defeated during automatic targeting.")
		return false
	if not (second_monster.get_node("HealthComponent") as HealthComponent).is_dead:
		_fail("Unit idled instead of attacking the remaining nearby enemy.")
		return false

	_remove_actors([archer, first_monster, second_monster])
	await process_frame
	return true


func _set_combat_enabled(actor: Node, enabled: bool) -> void:
	for component_name in ["MeleeAttackComponent", "RangedAttackComponent"]:
		var component := actor.get_node_or_null(component_name)
		if component != null:
			component.set("combat_enabled", enabled)


func _on_target_changed(target: Node2D) -> void:
	if target != null:
		target_history.append(target)


func _remove_actors(actors: Array) -> void:
	for actor in actors:
		if actor.get_parent() != null:
			actor.get_parent().remove_child(actor)
		actor.queue_free()


func _fail(message: String) -> void:
	push_error("T08 validation failed: %s" % message)
	quit(1)
