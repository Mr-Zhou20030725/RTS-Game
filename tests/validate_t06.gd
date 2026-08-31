extends SceneTree

const MAP_SCENE := preload("res://scenes/map/mvp_map.tscn")
const HUMAN_SCENE := preload("res://units/placeholders/test_unit.tscn")
const MONSTER_SCENE := preload("res://units/placeholders/test_monster.tscn")

var target_history: Array[Node2D] = []
var attack_event_count := 0


func _init() -> void:
	_run_validation()


func _run_validation() -> void:
	var map := MAP_SCENE.instantiate()
	root.add_child(map)
	await process_frame
	await physics_frame
	await physics_frame

	if not await _validate_human_chase_attack_and_retarget():
		return
	if not await _validate_target_escape_stops_chase():
		return
	if not await _validate_monster_can_attack_human():
		return

	print(
		"T06 validation passed: configurable melee damage/rate/range, chase, "
		+ "escape stop, death retarget, and no attacks against dead air."
	)
	quit()


func _validate_human_chase_attack_and_retarget() -> bool:
	target_history.clear()
	attack_event_count = 0

	var human := HUMAN_SCENE.instantiate()
	var first_monster := MONSTER_SCENE.instantiate()
	var second_monster := MONSTER_SCENE.instantiate()
	human.position = Vector2(300, 384)
	first_monster.position = Vector2(500, 384)
	second_monster.position = Vector2(650, 384)

	var human_health := human.get_node("HealthComponent") as HealthComponent
	human_health.max_health = 500.0
	var human_melee := human.get_node(
		"MeleeAttackComponent"
	) as MeleeAttackComponent
	human_melee.attack_damage = 40.0
	human_melee.attack_interval = 0.1
	human_melee.attack_range = 42.0
	human_melee.acquisition_range = 500.0
	human_melee.chase_range = 650.0
	human_melee.target_changed.connect(_on_target_changed)
	human_melee.attack_performed.connect(_on_attack_performed)

	for monster in [first_monster, second_monster]:
		var monster_health := monster.get_node(
			"HealthComponent"
		) as HealthComponent
		monster_health.max_health = 80.0
		var monster_melee := monster.get_node(
			"MeleeAttackComponent"
		) as MeleeAttackComponent
		monster_melee.combat_enabled = false

	root.add_child(human)
	root.add_child(first_monster)
	root.add_child(second_monster)
	await process_frame

	var human_start: Vector2 = human.global_position
	for _frame in 600:
		await physics_frame
		if (
			(first_monster.get_node("HealthComponent") as HealthComponent).is_dead
			and (
				second_monster.get_node("HealthComponent") as HealthComponent
			).is_dead
		):
			break

	var first_health := first_monster.get_node(
		"HealthComponent"
	) as HealthComponent
	var second_health := second_monster.get_node(
		"HealthComponent"
	) as HealthComponent
	if not first_health.is_dead or not second_health.is_dead:
		_fail(
			(
				"Swordsman did not defeat both targets: first_hp=%.1f, "
				+ "second_hp=%.1f, human_position=%s, target=%s, attacks=%d."
			)
			% [
				first_health.current_health,
				second_health.current_health,
				human.global_position,
				human_melee.get_current_target(),
				attack_event_count,
			]
		)
		return false
	if human.global_position.distance_to(human_start) < 100.0:
		_fail("Swordsman did not physically chase the first target.")
		return false
	if human.global_position.x <= first_monster.global_position.x + 60.0:
		_fail("Living unit could not move through the dead unit's former position.")
		return false
	for removed_group in [
		&"combat_targets",
		&"moving_units",
		&"selectable_units",
	]:
		if first_monster.is_in_group(removed_group):
			_fail("Dead unit remained in active group: %s." % removed_group)
			return false
	if first_monster.collision_layer != 0 or first_monster.collision_mask != 0:
		_fail("Dead unit retained an active physics collision layer or mask.")
		return false
	var corpse_shape := first_monster.get_node(
		"CollisionShape2D"
	) as CollisionShape2D
	if not corpse_shape.disabled:
		_fail("Dead unit collision shape was not disabled.")
		return false
	if not target_history.has(first_monster) or not target_history.has(second_monster):
		_fail("Swordsman did not reacquire the surviving enemy after death.")
		return false
	if attack_event_count < 4:
		_fail("Configured melee attacks did not emit expected attack events.")
		return false

	var attacks_after_deaths := attack_event_count
	for _frame in 120:
		await physics_frame
	if attack_event_count != attacks_after_deaths:
		_fail("Melee component continued attacking after all targets died.")
		return false
	if human_melee.get_current_target() != null:
		_fail("Dead target remained assigned after combat ended.")
		return false

	_remove_actors([human, first_monster, second_monster])
	await process_frame
	return true


func _validate_target_escape_stops_chase() -> bool:
	var human := HUMAN_SCENE.instantiate()
	var monster := MONSTER_SCENE.instantiate()
	human.position = Vector2(300, 300)
	monster.position = Vector2(480, 300)

	var human_melee := human.get_node(
		"MeleeAttackComponent"
	) as MeleeAttackComponent
	human_melee.attack_interval = 5.0
	human_melee.acquisition_range = 300.0
	human_melee.chase_range = 340.0
	(monster.get_node("MeleeAttackComponent") as MeleeAttackComponent).combat_enabled = false

	root.add_child(human)
	root.add_child(monster)
	for _frame in 20:
		await physics_frame
	if human_melee.get_current_target() != monster:
		_fail("Swordsman did not acquire a nearby hostile target.")
		return false

	monster.global_position = Vector2(1100, 620)
	for _frame in 20:
		await physics_frame
	if human_melee.get_current_target() != null:
		_fail("Target outside chase range was not released.")
		return false
	if human.call("has_move_target"):
		_fail("Unit continued chasing after its target escaped.")
		return false

	_remove_actors([human, monster])
	await process_frame
	return true


func _validate_monster_can_attack_human() -> bool:
	var human := HUMAN_SCENE.instantiate()
	var monster := MONSTER_SCENE.instantiate()
	human.position = Vector2(700, 300)
	monster.position = Vector2(730, 300)

	(human.get_node("MeleeAttackComponent") as MeleeAttackComponent).combat_enabled = false
	var monster_melee := monster.get_node(
		"MeleeAttackComponent"
	) as MeleeAttackComponent
	monster_melee.attack_damage = 15.0
	monster_melee.attack_interval = 0.1
	monster_melee.attack_range = 42.0
	var human_health := human.get_node("HealthComponent") as HealthComponent

	root.add_child(human)
	root.add_child(monster)
	await process_frame
	var health_before := human_health.current_health
	for _frame in 30:
		await physics_frame
		if human_health.current_health < health_before:
			break
	if not is_equal_approx(human_health.current_health, health_before - 15.0):
		_fail("Basic Monster did not apply configured melee damage to Human.")
		return false

	_remove_actors([human, monster])
	await process_frame
	return true


func _on_target_changed(target: Node2D) -> void:
	if target != null:
		target_history.append(target)


func _on_attack_performed(_target: Node2D, _damage: float) -> void:
	attack_event_count += 1


func _remove_actors(actors: Array) -> void:
	for actor in actors:
		if actor.get_parent() != null:
			actor.get_parent().remove_child(actor)
		actor.queue_free()


func _fail(message: String) -> void:
	push_error("T06 validation failed: %s" % message)
	quit(1)
