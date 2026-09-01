extends SceneTree

const ECONOMY_SCENE := preload("res://scenes/economy/human_economy.tscn")
const PLACEMENT_SCENE := preload(
	"res://scenes/building/building_placement_manager.tscn"
)
const BATTLE_SCENE := preload("res://scenes/battle/battle.tscn")
const TOWER_SCENE := preload("res://buildings/towers/defense_tower.tscn")
const MONSTER_SCENE := preload("res://units/placeholders/test_monster.tscn")
const ARROW_DATA := preload("res://resources/towers/arrow_tower.tres")
const FLAME_DATA := preload("res://resources/towers/flame_tower.tres")
const FROST_DATA := preload("res://resources/towers/frost_tower.tres")
const ARCANE_DATA := preload("res://resources/towers/arcane_tower.tres")


func _init() -> void:
	_run_validation()


func _run_validation() -> void:
	if not await _validate_build_buttons_visible_in_battle():
		return
	if not await _validate_data_driven_placement():
		return
	if not await _validate_arrow_single_target():
		return
	if not await _validate_flame_splash():
		return
	if not await _validate_frost_slow_and_restore():
		return
	if not await _validate_arcane_identity():
		return

	print(
		"T11 validation passed: four Resource-driven towers build independently; "
		+ "Arrow is single-target, Flame splashes, Frost slows then restores, "
		+ "and Arcane is slow but heavy-hitting."
	)
	quit()


func _validate_build_buttons_visible_in_battle() -> bool:
	var battle := BATTLE_SCENE.instantiate()
	root.add_child(battle)
	await process_frame
	await process_frame
	var hud := battle.get_node_or_null("HUDLayer/BattleHUD") as Control
	if hud == null or not hud.is_visible_in_tree():
		_fail("Battle HUD is not visible through its dedicated CanvasLayer.")
		return false
	var viewport_rect := Rect2(Vector2.ZERO, hud.get_viewport_rect().size)
	for button_name in [
		"ArrowTowerButton",
		"FlameTowerButton",
		"FrostTowerButton",
		"ArcaneTowerButton",
	]:
		var button := hud.find_child(button_name, true, false) as Button
		if button == null or not button.is_visible_in_tree():
			_fail("%s is missing or hidden in the battle HUD." % button_name)
			return false
		if not viewport_rect.intersects(button.get_global_rect()):
			_fail("%s is outside the visible viewport." % button_name)
			return false
	_cleanup([battle])
	await process_frame
	return true


func _validate_data_driven_placement() -> bool:
	var economy = ECONOMY_SCENE.instantiate()
	economy.starting_gold = 400
	economy.passive_income_amount = 0
	var placement = PLACEMENT_SCENE.instantiate()
	root.add_child(economy)
	root.add_child(placement)
	await process_frame

	var catalog: Array[Resource] = placement.get_tower_data_catalog()
	if catalog.size() < 4:
		_fail("The placement catalog does not retain all four core towers.")
		return false
	var expected_ids := [&"arrow", &"flame", &"frost", &"arcane"]
	var positions := [
		Vector2(160, 160), Vector2(320, 160),
		Vector2(480, 160), Vector2(640, 160),
	]
	for index in 4:
		if catalog[index].get("tower_id") != expected_ids[index]:
			_fail("Tower catalog order or identity is incorrect.")
			return false
		if not placement.begin_tower_placement(index, positions[index]):
			_fail("Could not begin placement for tower index %d." % index)
			return false
		if not placement.is_preview_position_valid():
			_fail("Tower index %d had an invalid preview on open terrain." % index)
			return false
		if not placement.confirm_placement():
			_fail("Could not independently build tower index %d." % index)
			return false

	var placed: Array[Node2D] = placement.get_placed_buildings()
	if placed.size() != 4 or economy.get_gold() != 100:
		_fail("Four-tower construction did not deduct the exact total cost of 300.")
		return false
	for index in 4:
		if placed[index].call("get_tower_data").get("tower_id") != expected_ids[index]:
			_fail("A placed tower did not retain its selected Resource.")
			return false

	var custom_data := ARROW_DATA.duplicate(true) as TowerData
	custom_data.cost = 137
	custom_data.damage = 41.0
	custom_data.attack_range = 444.0
	var custom_tower := TOWER_SCENE.instantiate()
	custom_tower.configure_tower(custom_data)
	root.add_child(custom_tower)
	await process_frame
	var ranged = custom_tower.get_node("RangedAttackComponent")
	if (
		not is_equal_approx(ranged.attack_damage, 41.0)
		or not is_equal_approx(ranged.attack_range, 444.0)
		or custom_tower.get_tower_data().cost != 137
	):
		_fail("Editing TowerData did not update tower damage, range, and cost.")
		return false

	_cleanup([economy, placement, custom_tower])
	await process_frame
	return true


func _validate_arrow_single_target() -> bool:
	var data := ARROW_DATA.duplicate(true) as TowerData
	data.attack_interval = 60.0
	data.projectile_speed = 3000.0
	var tower := await _spawn_tower(data, Vector2(200, 360))
	var primary := await _spawn_monster(Vector2(300, 360))
	var nearby := await _spawn_monster(Vector2(320, 375))
	var primary_health := primary.get_node("HealthComponent") as HealthComponent
	var nearby_health := nearby.get_node("HealthComponent") as HealthComponent
	var primary_start := primary_health.current_health
	var nearby_start := nearby_health.current_health
	if tower.get_node("RangedAttackComponent").fire_at(primary) == null:
		_fail("Arrow Tower could not fire at a legal target.")
		return false
	if not await _wait_for_damage(primary_health, primary_start):
		_fail("Arrow Tower projectile did not damage its target.")
		return false
	if (
		not is_equal_approx(primary_start - primary_health.current_health, data.damage)
		or not is_equal_approx(nearby_health.current_health, nearby_start)
	):
		_fail("Arrow Tower did not remain a single-target attack.")
		return false

	_cleanup([tower, primary, nearby])
	await process_frame
	return true


func _validate_flame_splash() -> bool:
	var data := FLAME_DATA.duplicate(true) as TowerData
	data.attack_interval = 60.0
	data.projectile_speed = 3000.0
	var tower := await _spawn_tower(data, Vector2(200, 360))
	var primary := await _spawn_monster(Vector2(300, 360))
	var nearby := await _spawn_monster(Vector2(335, 375))
	var primary_health := primary.get_node("HealthComponent") as HealthComponent
	var nearby_health := nearby.get_node("HealthComponent") as HealthComponent
	var primary_start := primary_health.current_health
	var nearby_start := nearby_health.current_health
	tower.get_node("RangedAttackComponent").fire_at(primary)
	if not await _wait_for_damage(primary_health, primary_start):
		_fail("Flame Tower projectile did not reach its target.")
		return false
	if (
		not is_equal_approx(primary_start - primary_health.current_health, data.damage)
		or not is_equal_approx(nearby_start - nearby_health.current_health, data.damage)
	):
		_fail("Flame Tower did not apply area damage to a nearby enemy.")
		return false

	_cleanup([tower, primary, nearby])
	await process_frame
	return true


func _validate_frost_slow_and_restore() -> bool:
	var data := FROST_DATA.duplicate(true) as TowerData
	data.attack_interval = 60.0
	data.projectile_speed = 3000.0
	data.slow_duration = 0.2
	var tower := await _spawn_tower(data, Vector2(200, 360))
	var monster := await _spawn_monster(Vector2(300, 360))
	var health := monster.get_node("HealthComponent") as HealthComponent
	var health_start := health.current_health
	tower.get_node("RangedAttackComponent").fire_at(monster)
	if not await _wait_for_damage(health, health_start):
		_fail("Frost Tower projectile did not reach its target.")
		return false
	if not is_equal_approx(
		monster.get_effective_move_speed(), monster.move_speed * data.slow_multiplier
	):
		_fail("Frost Tower did not apply its configured movement slow.")
		return false
	for _frame in 30:
		await physics_frame
	if (
		not is_equal_approx(monster.get_effective_move_speed(), monster.move_speed)
		or not is_zero_approx(monster.get_movement_slow_remaining())
	):
		_fail("Frost slow did not restore normal speed after expiration.")
		return false

	_cleanup([tower, monster])
	await process_frame
	return true


func _validate_arcane_identity() -> bool:
	if (
		ARCANE_DATA.damage <= ARROW_DATA.damage
		or ARCANE_DATA.attack_interval <= ARROW_DATA.attack_interval
		or ARCANE_DATA.attack_range <= ARROW_DATA.attack_range
	):
		_fail("Arcane Tower is not configured as a slow, heavy, long-range tower.")
		return false
	var data := ARCANE_DATA.duplicate(true) as TowerData
	data.attack_interval = 60.0
	data.projectile_speed = 3000.0
	var tower := await _spawn_tower(data, Vector2(200, 360))
	var monster := await _spawn_monster(Vector2(300, 360))
	var health := monster.get_node("HealthComponent") as HealthComponent
	var health_start := health.current_health
	tower.get_node("RangedAttackComponent").fire_at(monster)
	if not await _wait_for_damage(health, health_start):
		_fail("Arcane Tower projectile did not reach its target.")
		return false
	if not is_equal_approx(health_start - health.current_health, ARCANE_DATA.damage):
		_fail("Arcane Tower did not apply its configured heavy damage.")
		return false

	_cleanup([tower, monster])
	await process_frame
	return true


func _spawn_tower(data: TowerData, position: Vector2) -> Node2D:
	var tower := TOWER_SCENE.instantiate() as Node2D
	tower.call("configure_tower", data)
	tower.position = position
	root.add_child(tower)
	await process_frame
	return tower


func _spawn_monster(position: Vector2) -> Node2D:
	var monster := MONSTER_SCENE.instantiate() as Node2D
	monster.position = position
	(monster.get_node("MeleeAttackComponent") as MeleeAttackComponent).combat_enabled = false
	root.add_child(monster)
	await process_frame
	return monster


func _wait_for_damage(health: HealthComponent, starting_health: float) -> bool:
	for _frame in 30:
		await physics_frame
		if health.current_health < starting_health:
			return true
	return false


func _cleanup(nodes: Array) -> void:
	for node in nodes:
		if node != null and is_instance_valid(node):
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.queue_free()
	for projectile in get_nodes_in_group(&"combat_projectiles"):
		if projectile.get_parent() != null:
			projectile.get_parent().remove_child(projectile)
		projectile.queue_free()


func _fail(message: String) -> void:
	push_error("T11 validation failed: %s" % message)
	quit(1)
