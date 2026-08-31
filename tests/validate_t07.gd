extends SceneTree

const ARCHER_SCENE := preload("res://units/placeholders/test_archer.tscn")
const MONSTER_SCENE := preload("res://units/placeholders/test_monster.tscn")

var projectile_count := 0
var observed_damage := 0.0
var observed_speed := 0.0


func _init() -> void:
	_run_validation()


func _run_validation() -> void:
	if not await _validate_projectile_hits_with_configured_parameters():
		return
	if not await _validate_projectiles_expire_when_target_dies_early():
		return

	print(
		"T07 validation passed: ranged attacks launch configurable projectiles, "
		+ "hit enemies, and safely expire when their target dies early."
	)
	quit()


func _validate_projectile_hits_with_configured_parameters() -> bool:
	projectile_count = 0
	observed_damage = 0.0
	observed_speed = 0.0

	var archer := ARCHER_SCENE.instantiate()
	var monster := MONSTER_SCENE.instantiate()
	archer.position = Vector2(240, 300)
	monster.position = Vector2(500, 300)

	var ranged = archer.get_node("RangedAttackComponent")
	ranged.attack_damage = 25.0
	ranged.attack_interval = 0.12
	ranged.attack_range = 400.0
	ranged.projectile_speed = 260.0
	ranged.projectile_fired.connect(_on_projectile_fired)

	var monster_health := monster.get_node(
		"HealthComponent"
	) as HealthComponent
	monster_health.max_health = 75.0
	(monster.get_node("MeleeAttackComponent") as MeleeAttackComponent).combat_enabled = false

	root.add_child(archer)
	root.add_child(monster)
	for _frame in 240:
		await physics_frame
		if monster_health.is_dead:
			break

	if not monster_health.is_dead:
		_fail("Configured ranged projectiles did not defeat the target.")
		return false
	if projectile_count < 3:
		_fail("Ranged component did not launch the expected projectiles.")
		return false
	if not is_equal_approx(observed_damage, 25.0):
		_fail("Projectile did not inherit the configured attack damage.")
		return false
	if not is_equal_approx(observed_speed, 260.0):
		_fail("Projectile did not inherit the configured projectile speed.")
		return false

	for _frame in 5:
		await physics_frame
	if not get_nodes_in_group("combat_projectiles").is_empty():
		_fail("Projectile remained active after its target died.")
		return false

	_remove_actors([archer, monster])
	await process_frame
	return true


func _validate_projectiles_expire_when_target_dies_early() -> bool:
	var archer := ARCHER_SCENE.instantiate()
	var monster := MONSTER_SCENE.instantiate()
	archer.position = Vector2(200, 500)
	monster.position = Vector2(520, 500)

	var ranged = archer.get_node("RangedAttackComponent")
	ranged.attack_damage = 10.0
	ranged.attack_interval = 60.0
	ranged.attack_range = 500.0
	ranged.projectile_speed = 90.0
	(monster.get_node("MeleeAttackComponent") as MeleeAttackComponent).combat_enabled = false

	root.add_child(archer)
	root.add_child(monster)
	await process_frame

	ranged.attack_range = 100.0
	if ranged.fire_at(monster) != null:
		_fail("Ranged attack ignored its configured attack range.")
		return false
	ranged.attack_range = 500.0
	var first_projectile: Node2D = ranged.fire_at(monster)
	var second_projectile: Node2D = ranged.fire_at(monster)
	if first_projectile == null or second_projectile == null:
		_fail("Could not launch projectiles for the early-death safety test.")
		return false

	CombatRules.try_apply_damage(archer, monster, 100000.0)
	for _frame in 5:
		await physics_frame
	if is_instance_valid(first_projectile) or is_instance_valid(second_projectile):
		_fail("Projectile did not free itself after its target died early.")
		return false
	if not get_nodes_in_group("combat_projectiles").is_empty():
		_fail("An orphaned projectile remained after target invalidation.")
		return false

	_remove_actors([archer, monster])
	await process_frame
	return true


func _on_projectile_fired(
	projectile: Node2D, _target: Node2D
) -> void:
	projectile_count += 1
	observed_damage = projectile.get("damage")
	observed_speed = projectile.get("projectile_speed")


func _remove_actors(actors: Array) -> void:
	for actor in actors:
		if actor.get_parent() != null:
			actor.get_parent().remove_child(actor)
		actor.queue_free()


func _fail(message: String) -> void:
	push_error("T07 validation failed: %s" % message)
	quit(1)
