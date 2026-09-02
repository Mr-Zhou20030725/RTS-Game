extends SceneTree

const BATTLE_SCENE := preload("res://scenes/battle/battle.tscn")

const EXPECTED_STAGE_IDS: Array[StringName] = [
	&"normal", &"wrath_one", &"wrath_two", &"dark_mother",
]
const EXPECTED_HEALTH_MULTIPLIERS := [1.0, 1.15, 1.5, 2.25]
const EXPECTED_INCOME_MULTIPLIERS := [1.0, 1.25, 1.75, 3.0]
const EXPECTED_COST_MULTIPLIERS := [1.0, 0.95, 0.85, 0.7]
const EXPECTED_TOTAL_INCOME := [8, 8, 7, 6]
const EXPECTED_GOBLIN_COST := [15, 14, 13, 11]


func _init() -> void:
	_run_validation()


func _run_validation() -> void:
	var battle := BATTLE_SCENE.instantiate()
	root.add_child(battle)
	await process_frame
	await process_frame
	var map := battle.get_node("MVPMap")
	var strengthening := battle.get_node(
		"NestStrengtheningManager"
	) as NestStrengtheningManager
	var economy := battle.get_node("MonsterEconomy") as MonsterEconomy
	var production := battle.get_node(
		"MonsterProductionManager"
	) as MonsterProductionManager
	var fog := battle.get_node("FogOfWarManager") as FogOfWarManager
	var hud := battle.get_node("HUDLayer/BattleHUD") as Control
	economy.set_process(false)
	fog.set_human_fog_enabled(false)

	if strengthening.stage_profiles.size() != 4:
		_fail("The strengthening table does not contain four data profiles.")
		return
	var final_nest := map.get_active_nests()[0] as Node2D
	var final_health := final_nest.get_node(
		"HealthComponent"
	) as HealthComponent
	final_health.take_damage(60.0)
	if not _validate_stage(
		4, 0, map, strengthening, economy, production, final_nest
	):
		return

	for stage_index in range(1, 4):
		var victim := _find_victim(map.get_active_nests(), final_nest)
		if victim == null:
			_fail("Could not find the next non-final nest to destroy.")
			return
		production.select_nest(victim)
		var victim_health := victim.get_node(
			"HealthComponent"
		) as HealthComponent
		victim_health.take_damage(victim_health.max_health * 2.0)
		await process_frame
		if production.get_selected_nest() != null:
			_fail("Destroying a selected nest left a stale production reference.")
			return
		var remaining_count := 4 - stage_index
		if not _validate_stage(
			remaining_count,
			stage_index,
			map,
			strengthening,
			economy,
			production,
			final_nest
		):
			return

	if final_health.max_health <= 600.0 * 2.0:
		_fail("The Dark Mother Nest is not clearly tougher than an initial nest.")
		return
	if economy.get_income_per_interval() <= economy.energy_per_nest:
		_fail("The final nest does not generate more energy than one initial nest.")
		return
	if production.get_effective_cost(0) >= 15:
		_fail("The final nest did not gain its configured production efficiency.")
		return

	production.select_nest(final_nest)
	var energy_before := economy.get_dark_energy()
	if not production.produce(0):
		_fail("The Dark Mother Nest could not produce a monster.")
		return
	if economy.get_dark_energy() != energy_before - 11:
		_fail("Dark Mother production did not use its exact discounted cost.")
		return
	var panel := hud.get_node("MonsterProductionPanel") as ColorRect
	var stage_label := panel.get_node("NestStageLabel") as Label
	var grunt_button := panel.get_node("MonsterTypeZeroButton") as Button
	if (
		not panel.visible
		or stage_label.text != "黑暗母巢"
		or "11 暗能量" not in grunt_button.text
	):
		_fail("The production HUD did not show the final stage and cost.")
		return

	print(
		"T19 validation passed: every destroyed nest advances a data-driven "
		+ "strength stage, remaining nests preserve health ratio while gaining "
		+ "max HP, per-nest income and production efficiency, the Dark Mother "
		+ "Nest is visibly stronger, and selected destroyed nests leave no stale references."
	)
	quit()


func _validate_stage(
	remaining_count: int,
	stage_index: int,
	map: Node,
	strengthening: NestStrengtheningManager,
	economy: MonsterEconomy,
	production: MonsterProductionManager,
	final_nest: Node2D
) -> bool:
	var profile := strengthening.get_current_profile()
	if (
		map.call("get_active_nest_count") != remaining_count
		or profile == null
		or profile.stage_id != EXPECTED_STAGE_IDS[stage_index]
	):
		_fail("The active nest count selected the wrong strengthening stage.")
		return false
	if (
		not is_equal_approx(
			profile.max_health_multiplier,
			EXPECTED_HEALTH_MULTIPLIERS[stage_index]
		)
		or not is_equal_approx(
			profile.energy_per_nest_multiplier,
			EXPECTED_INCOME_MULTIPLIERS[stage_index]
		)
		or not is_equal_approx(
			profile.production_cost_multiplier,
			EXPECTED_COST_MULTIPLIERS[stage_index]
		)
	):
		_fail("A strengthening profile does not match its data resource.")
		return false
	if (
		economy.get_income_per_interval()
		!= EXPECTED_TOTAL_INCOME[stage_index]
		or production.get_effective_cost(0)
		!= EXPECTED_GOBLIN_COST[stage_index]
	):
		_fail("Economy or production did not apply the current stage multipliers.")
		return false
	var final_health := final_nest.get_node(
		"HealthComponent"
	) as HealthComponent
	if not is_equal_approx(
		final_health.max_health,
		600.0 * EXPECTED_HEALTH_MULTIPLIERS[stage_index]
	):
		_fail("A surviving nest received an incorrect maximum health value.")
		return false
	if not is_equal_approx(final_health.get_health_ratio(), 0.9):
		_fail("Strengthening healed or damaged a nest instead of preserving its ratio.")
		return false
	for nest_value in map.call("get_active_nests"):
		var nest := nest_value as Node2D
		if nest == null or not is_instance_valid(nest):
			_fail("The active nest list contains a stale reference.")
			return false
		if nest.get_meta(&"nest_strength_stage", &"") != profile.stage_id:
			_fail("A remaining nest did not receive the current stage metadata.")
			return false
	return true


func _find_victim(nests: Array[Node2D], final_nest: Node2D) -> Node2D:
	for nest in nests:
		if nest != final_nest:
			return nest
	return null


func _fail(message: String) -> void:
	push_error("T19 validation failed: %s" % message)
	quit(1)
