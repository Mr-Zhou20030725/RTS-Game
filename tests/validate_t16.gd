extends SceneTree

const TargetSelector := preload("res://scripts/combat/targeting_service.gd")
const MAP_SCENE := preload("res://scenes/map/mvp_map.tscn")
const FOG_SCENE := preload("res://scenes/visibility/fog_of_war_manager.tscn")
const HUMAN_ARCHER_SCENE := preload("res://units/placeholders/test_archer.tscn")
const HUMAN_SWORDSMAN_SCENE := preload("res://units/placeholders/test_unit.tscn")

var nest_count_history: Array[int] = []
var destroyed_signal_count := 0
var destroyed_nest_id := 0


func _init() -> void:
	_run_validation()


func _run_validation() -> void:
	var map := MAP_SCENE.instantiate()
	map.generation_seed = 3
	map.active_nest_count_changed.connect(_on_active_nest_count_changed)
	map.nest_destroyed.connect(_on_nest_destroyed)
	var fog := FOG_SCENE.instantiate()
	var archer := HUMAN_ARCHER_SCENE.instantiate() as Node2D
	var ranged := archer.get_node("RangedAttackComponent") as RangedAttackComponent
	ranged.combat_enabled = false
	root.add_child(map)
	root.add_child(fog)
	root.add_child(archer)
	await process_frame
	await physics_frame

	if map.get_active_nest_count() != 4 or nest_count_history != [4]:
		_fail("Map did not publish the initial four active nests.")
		return
	archer.global_position = map.human_base.global_position
	fog.refresh_visibility()
	var target_nest := map.get_active_nests()[0] as Node2D
	var target_id := target_nest.get_instance_id()
	if not target_nest.is_in_group(&"combat_targets"):
		_fail("Monster nests are not available to the shared combat target search.")
		return
	if target_nest.visible or CombatRules.can_damage(archer, target_nest):
		_fail("A nest hidden in fog could be confirmed or locked by a Human unit.")
		return
	if TargetSelector.find_best_target_in_group(
		archer, &"combat_targets", INF
	) != null:
		_fail("Automatic targeting leaked a nest hidden in fog.")
		return

	var reveal_position := target_nest.global_position + (
		target_nest.global_position.direction_to(map.human_base.global_position)
		* 110.0
	)
	archer.global_position = reveal_position
	fog.refresh_visibility()
	if not target_nest.visible or not CombatRules.can_damage(archer, target_nest):
		_fail("A nest inside Human vision was not visible and targetable.")
		return
	if TargetSelector.find_best_target_in_group(
		archer, &"combat_targets", 300.0
	) != target_nest:
		_fail("Human automatic targeting did not acquire the revealed nest.")
		return

	ranged.attack_damage = 700.0
	ranged.attack_interval = 0.05
	ranged.attack_range = 300.0
	ranged.projectile_speed = 5000.0
	ranged.combat_enabled = true
	for _frame in 180:
		await physics_frame
		if map.get_active_nest_count() == 3:
			break
	if map.get_active_nest_count() != 3:
		_fail("Human ranged combat did not destroy the revealed nest.")
		return
	if (
		destroyed_signal_count != 1
		or destroyed_nest_id != target_id
		or nest_count_history != [4, 3]
	):
		_fail("Nest death did not publish one correct active-count update.")
		return
	for active_nest in map.get_active_nests():
		if not is_instance_valid(active_nest):
			_fail("Active nest list retained an invalid reference.")
			return
		var health := active_nest.get_node("HealthComponent") as HealthComponent
		if health.is_dead:
			_fail("Active nest list retained a destroyed nest.")
			return
	for candidate in get_nodes_in_group(&"combat_targets"):
		if candidate.get_instance_id() == target_id:
			_fail("Destroyed nest remained in the combat target group.")
			return
	for _frame in 30:
		await physics_frame
	if ranged.get_current_target() != null:
		_fail("Ranged combat retained a target after the nest was freed.")
		return
	ranged.combat_enabled = false
	var swordsman := HUMAN_SWORDSMAN_SCENE.instantiate() as Node2D
	if not await _validate_manual_move_override(map, fog, swordsman):
		return

	_cleanup([map, fog, archer, swordsman])
	await process_frame
	print(
		"T16 validation passed: fog-hidden nests cannot be locked, revealed nests "
		+ "are acquired and destroyed by Human units, and active nest count/list "
		+ "update exactly once without stale targets; manual movement overrides "
		+ "automatic nest pursuit."
	)
	quit()


func _validate_manual_move_override(
	map: Node2D, fog: FogOfWarManager, swordsman: Node2D
) -> bool:
	var target_nest := map.get_active_nests()[0] as Node2D
	var melee := swordsman.get_node(
		"MeleeAttackComponent"
	) as MeleeAttackComponent
	melee.attack_damage = 1.0
	melee.attack_interval = 60.0
	melee.acquisition_range = 300.0
	melee.chase_range = 500.0
	swordsman.global_position = target_nest.global_position + (
		target_nest.global_position.direction_to(map.human_base.global_position)
		* 100.0
	)
	root.add_child(swordsman)
	fog.refresh_visibility()
	for _frame in 30:
		await physics_frame
		if melee.get_current_target() == target_nest:
			break
	if melee.get_current_target() != target_nest:
		_fail("Swordsman did not acquire a revealed nest for move override test.")
		return false

	var start_position := swordsman.global_position
	var destination: Vector2 = (
		(map.get("human_base") as Node2D).global_position
	)
	swordsman.call("move_to", destination)
	if (
		melee.get_current_target() != null
		or not swordsman.call("is_manual_move_order_active")
	):
		_fail("Manual move order did not immediately release the nest target.")
		return false
	for _frame in 60:
		await physics_frame
		if melee.get_current_target() != null:
			_fail("Automatic melee targeting overrode an active manual move order.")
			return false
	if (
		swordsman.global_position.distance_to(start_position) < 50.0
		or swordsman.global_position.distance_to(destination)
		>= start_position.distance_to(destination)
	):
		_fail("Swordsman could not move away after encountering a nest.")
		return false
	return true


func _on_active_nest_count_changed(current_count: int) -> void:
	nest_count_history.append(current_count)


func _on_nest_destroyed(nest: Node2D, _remaining_count: int) -> void:
	destroyed_signal_count += 1
	destroyed_nest_id = nest.get_instance_id()


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
	push_error("T16 validation failed: %s" % message)
	quit(1)
