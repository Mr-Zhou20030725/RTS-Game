extends SceneTree

const BATTLE_SCENE := preload("res://scenes/battle/battle.tscn")


func _init() -> void:
	_run_validation()


func _run_validation() -> void:
	if not await _validate_human_victory():
		return
	paused = false
	if not await _validate_monster_victory():
		return
	paused = false
	if not await _validate_restart_flow():
		return
	print(
		"T30 validation passed: both destruction win conditions resolve once, "
		+ "pause combat, show the correct player result, and expose restart controls."
	)
	quit(0)


func _validate_human_victory() -> bool:
	var battle := await _spawn_battle()
	var result := battle.get_node(
		"BattleResultManager"
	) as BattleResultManager
	var map := battle.get_node("MVPMap") as Node2D
	result.configure_dependencies(map, GameManager.PlayerFaction.HUMAN)
	var result_count := [0]
	result.result_declared.connect(
		func(_winner: BattleResultManager.Winner, _player_won: bool) -> void:
			result_count[0] += 1
	)
	var nests: Array[Node2D] = map.call("get_active_nests")
	if nests.size() != 4:
		return _fail_battle(battle, "Human victory test did not start with four nests.")
	for nest in nests:
		var health := nest.get_node("HealthComponent") as HealthComponent
		health.take_damage(health.max_health)
	if (
		result.get_winner() != BattleResultManager.Winner.HUMAN
		or not result.is_player_victorious()
		or result_count[0] != 1
		or not paused
		or not result.overlay.visible
		or result.result_title.text != "胜利"
		or "全部怪物巢穴" not in result.reason_label.text
	):
		return _fail_battle(
			battle,
			"Destroying all nests did not produce one paused Human victory."
		)
	if (
		result.declare_result(BattleResultManager.Winner.MONSTER)
		or result_count[0] != 1
	):
		return _fail_battle(battle, "A completed battle accepted a second result.")
	if (
		result.process_mode != Node.PROCESS_MODE_ALWAYS
		or not result.restart_button.visible
		or result.restart_button.text != "重新开始"
		or root.get_node_or_null("GameManager") == null
		or not root.get_node("GameManager").has_method("restart_battle")
	):
		return _fail_battle(
			battle,
			"Result controls are unavailable while the battle is paused."
		)
	paused = false
	root.remove_child(battle)
	battle.queue_free()
	await process_frame
	return true


func _validate_monster_victory() -> bool:
	var battle := await _spawn_battle()
	var result := battle.get_node(
		"BattleResultManager"
	) as BattleResultManager
	var map := battle.get_node("MVPMap") as Node2D
	result.configure_dependencies(map, GameManager.PlayerFaction.HUMAN)
	var human_base := map.get("human_base") as Node2D
	var health := human_base.get_node("HealthComponent") as HealthComponent
	health.take_damage(health.max_health)
	if (
		result.get_winner() != BattleResultManager.Winner.MONSTER
		or result.is_player_victorious()
		or not paused
		or result.result_title.text != "失败"
		or "人类基地" not in result.reason_label.text
	):
		return _fail_battle(
			battle,
			"Destroying the Human base did not produce a paused player defeat."
		)
	paused = false
	root.remove_child(battle)
	battle.queue_free()
	await process_frame
	return true


func _validate_restart_flow() -> bool:
	var game_manager := root.get_node_or_null("GameManager")
	if game_manager == null:
		return _fail("GameManager autoload is unavailable for restart validation.")
	game_manager.set(
		"selected_player_faction", GameManager.PlayerFaction.MONSTER
	)
	paused = true
	game_manager.call("restart_battle")
	await process_frame
	await process_frame
	await process_frame
	if (
		paused
		or current_scene == null
		or current_scene.name != "Battle"
		or int(current_scene.call("get_player_faction"))
		!= GameManager.PlayerFaction.MONSTER
		or current_scene.get_node("BattleResultManager").overlay.visible
	):
		return _fail(
			"Restart did not load a fresh unpaused battle with the same faction."
		)
	return true


func _spawn_battle() -> Node2D:
	paused = false
	var battle := BATTLE_SCENE.instantiate() as Node2D
	root.add_child(battle)
	await process_frame
	await process_frame
	await process_frame
	battle.get_node("HumanAIController").call("set_ai_enabled", false)
	battle.get_node("MonsterAIController").call("set_ai_enabled", false)
	battle.get_node("GameTimeManager").set_process(false)
	battle.get_node("HumanEconomy").set_process(false)
	battle.get_node("MonsterEconomy").set_process(false)
	return battle


func _fail_battle(battle: Node, message: String) -> bool:
	paused = false
	if battle != null and is_instance_valid(battle):
		root.remove_child(battle)
		battle.queue_free()
	return _fail(message)


func _fail(message: String) -> bool:
	paused = false
	push_error("T30 validation failed: %s" % message)
	quit(1)
	return false
