extends SceneTree

const MAP_SCENE := preload("res://scenes/map/mvp_map.tscn")
const ECONOMY_SCENE := preload("res://scenes/economy/human_economy.tscn")
const SQUAD_MANAGER_SCENE := preload(
	"res://scenes/units/human_squad_manager.tscn"
)
const HUD_SCENE := preload("res://ui/battle_hud/battle_hud.tscn")
const SELECTION_SCRIPT := preload(
	"res://scripts/input/unit_selection_manager.gd"
)
const MONSTER_SCENE := preload("res://units/placeholders/test_monster.tscn")


func _init() -> void:
	_run_validation()


func _run_validation() -> void:
	if not await _validate_recruitment_roles_and_group_movement():
		return
	if not await _validate_insufficient_gold():
		return
	print(
		"T13 validation passed: all four data-driven recruit actions spawn one "
		+ "soldier at distinct costs, preserve clear combat roles, respond to "
		+ "movement commands, and reject unaffordable recruits."
	)
	quit()


func _validate_recruitment_roles_and_group_movement() -> bool:
	var map := MAP_SCENE.instantiate()
	var economy = ECONOMY_SCENE.instantiate()
	economy.starting_gold = 1000
	economy.passive_income_amount = 0
	var manager = SQUAD_MANAGER_SCENE.instantiate()
	var selection = SELECTION_SCRIPT.new()
	var hud := HUD_SCENE.instantiate()
	root.add_child(map)
	root.add_child(economy)
	root.add_child(manager)
	root.add_child(selection)
	root.add_child(hud)
	await process_frame
	await physics_frame

	var catalog: Array[Resource] = manager.get_squad_catalog()
	if catalog.size() != 4:
		_fail("Recruitment catalog does not contain four Human squads.")
		return false
	var expected_ids := [&"swordsman", &"archer", &"knight", &"mage"]
	var expected_costs := [60, 80, 110, 130]
	var expected_members := [1, 1, 1, 1]
	var expected_speeds := [75.0, 84.0, 126.0, 72.0]
	var starting_gold: int = economy.get_gold()

	var sword_button := hud.get_node(
		"SquadRecruitBar/SwordsmanSquadButton"
	) as Button
	if sword_button == null or not sword_button.is_visible_in_tree():
		_fail("Swordsman recruitment button is not visible in the HUD.")
		return false
	sword_button.pressed.emit()
	for index in range(1, 4):
		if not manager.recruit_squad(index):
			_fail("Could not recruit squad index %d." % index)
			return false

	var squads: Array[Node2D] = manager.get_recruited_squads()
	if squads.size() != 4:
		_fail("Four recruitment actions did not create four squad groups.")
		return false
	if manager.z_index <= map.get_node("Ground").z_index:
		_fail("Recruited units are not drawn above the map terrain layer.")
		return false
	var battlefield_rect := Rect2(64, 80, 1152, 608)
	for bar_name in ["SquadRecruitBar", "TowerBuildBar"]:
		var command_bar := hud.get_node(bar_name) as Control
		if command_bar.get_global_rect().intersects(battlefield_rect):
			_fail("%s overlaps the playable battlefield." % bar_name)
			return false
	var total_cost := 0
	for cost in expected_costs:
		total_cost += cost
	if economy.get_gold() != starting_gold - total_cost:
		_fail("Squad recruitment did not deduct the four configured costs.")
		return false

	for index in 4:
		var data = catalog[index]
		if data.get("squad_id") != expected_ids[index]:
			_fail("Squad catalog identity or order is incorrect.")
			return false
		if int(data.get("cost")) != expected_costs[index]:
			_fail("Squad index %d does not use its distinct data cost." % index)
			return false
		if not is_equal_approx(float(data.get("move_speed")), expected_speeds[index]):
			_fail("Human movement speed does not use the reduced balance value.")
			return false
		if squads[index].get_child_count() != expected_members[index]:
			_fail("One purchase did not spawn exactly one soldier.")
			return false
		var instance_ids: Dictionary[StringName, bool] = {}
		for member in squads[index].get_children():
			instance_ids[member.call("get_squad_instance_id")] = true
			if not member.is_visible_in_tree():
				_fail("A recruited squad member is hidden in the scene tree.")
				return false
			if member.scale != Vector2(0.975, 0.975):
				_fail("A recruited soldier does not use the reduced art scale.")
				return false
			if member.global_position.y >= 3880.0:
				_fail("A recruited member spawned inside the command dock.")
				return false
			_disable_combat(member)
		if instance_ids.size() != 1:
			_fail("Members from one recruitment do not share one squad ID.")
			return false

	var swordsman := squads[0].get_child(0)
	var archer := squads[1].get_child(0)
	var knight := squads[2].get_child(0)
	var mage := squads[3].get_child(0)
	if (
		swordsman.get_node("HealthComponent").max_health
		<= archer.get_node("HealthComponent").max_health
	):
		_fail("Swordsmen are not tougher front-line units than Archers.")
		return false
	if (
		catalog[0].get("attack_style") != HumanSquadData.AttackStyle.MELEE
		or catalog[1].get("attack_style") != HumanSquadData.AttackStyle.RANGED
		or catalog[2].get("move_speed") <= catalog[0].get("move_speed")
		or catalog[3].get("attack_style")
		!= HumanSquadData.AttackStyle.SPLASH_RANGED
		or catalog[3].get("splash_radius") <= 0.0
	):
		_fail("Swordsman, Archer, Knight, and Mage roles are not distinct.")
		return false
	if knight.move_speed <= archer.move_speed:
		_fail("Knight members are not observably faster than Archers.")
		return false

	selection.select_single(swordsman)
	var selected: Array[Node2D] = selection.get_selected_units()
	if selected.size() != expected_members[0]:
		_fail("Selecting a recruited soldier did not select that soldier.")
		return false
	var start_centroid := _centroid(selected)
	# Move away from the other freshly spawned squads so they cannot body-block
	# this formation during the concentration check.
	selection.issue_move_command(Vector2(1600, 2400))
	if not _move_targets_are_compact_and_unique(selected):
		_fail("Squad move order did not create a compact unique formation.")
		return false
	for _frame in 180:
		await physics_frame
	var end_centroid := _centroid(selected)
	if end_centroid.distance_to(start_centroid) < 120.0:
		_fail("Recruited squad did not move toward its group order.")
		return false
	if _maximum_pair_distance(selected) > 130.0:
		_fail("Members of one squad spread too far apart after moving.")
		return false

	if not await _validate_mage_area_damage(mage):
		return false

	_cleanup([map, economy, manager, selection, hud])
	await process_frame
	return true


func _validate_mage_area_damage(mage: Node2D) -> bool:
	mage.global_position = Vector2(300, 300)
	var ranged = mage.get_node("RangedAttackComponent") as RangedAttackComponent
	ranged.combat_enabled = true
	ranged.attack_interval = 60.0
	ranged.projectile_speed = 3000.0
	ranged.clear_target()
	var primary := MONSTER_SCENE.instantiate()
	var nearby := MONSTER_SCENE.instantiate()
	primary.position = Vector2(390, 300)
	nearby.position = Vector2(425, 315)
	_disable_combat(primary)
	_disable_combat(nearby)
	root.add_child(primary)
	root.add_child(nearby)
	await process_frame
	var primary_health := primary.get_node("HealthComponent") as HealthComponent
	var nearby_health := nearby.get_node("HealthComponent") as HealthComponent
	var primary_start := primary_health.current_health
	var nearby_start := nearby_health.current_health
	if ranged.fire_at(primary) == null:
		_fail("Mage could not launch its configured ranged attack.")
		return false
	for _frame in 30:
		await physics_frame
		if primary_health.current_health < primary_start:
			break
	if (
		primary_health.current_health >= primary_start
		or nearby_health.current_health >= nearby_start
	):
		_fail("Mage attack did not apply observable area damage.")
		return false
	_cleanup([primary, nearby])
	return true


func _validate_insufficient_gold() -> bool:
	var economy = ECONOMY_SCENE.instantiate()
	economy.starting_gold = 50
	economy.passive_income_amount = 0
	var manager = SQUAD_MANAGER_SCENE.instantiate()
	root.add_child(economy)
	root.add_child(manager)
	await process_frame
	if manager.recruit_squad(0):
		_fail("A 60-gold squad was recruited with only 50 gold.")
		return false
	if economy.get_gold() != 50 or not manager.get_recruited_squads().is_empty():
		_fail("Rejected recruitment changed gold or spawned a squad.")
		return false
	_cleanup([economy, manager])
	await process_frame
	return true


func _disable_combat(actor: Node) -> void:
	var melee := actor.get_node_or_null("MeleeAttackComponent")
	if melee != null:
		melee.set("combat_enabled", false)
	var ranged := actor.get_node_or_null("RangedAttackComponent")
	if ranged != null:
		ranged.set("combat_enabled", false)


func _centroid(units: Array[Node2D]) -> Vector2:
	var total := Vector2.ZERO
	for unit in units:
		total += unit.global_position
	return total / float(units.size())


func _maximum_pair_distance(units: Array[Node2D]) -> float:
	var maximum := 0.0
	for index in units.size():
		for other_index in range(index + 1, units.size()):
			maximum = maxf(
				maximum,
				units[index].global_position.distance_to(
					units[other_index].global_position
				)
			)
	return maximum


func _move_targets_are_compact_and_unique(units: Array[Node2D]) -> bool:
	var targets: Dictionary[Vector2, bool] = {}
	for unit in units:
		targets[unit.call("get_move_target")] = true
	if targets.size() != units.size():
		return false
	var target_array: Array[Vector2] = []
	for target in targets:
		target_array.append(target)
	return _maximum_pair_distance_for_positions(target_array) <= 100.0


func _maximum_pair_distance_for_positions(positions: Array[Vector2]) -> float:
	var maximum := 0.0
	for index in positions.size():
		for other_index in range(index + 1, positions.size()):
			maximum = maxf(
				maximum, positions[index].distance_to(positions[other_index])
			)
	return maximum


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
	push_error("T13 validation failed: %s" % message)
	quit(1)
