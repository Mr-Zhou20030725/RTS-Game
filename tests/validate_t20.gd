extends SceneTree

const BATTLE_SCENE := preload("res://scenes/battle/battle.tscn")

const EXPECTED_IDS: Array[StringName] = [
	&"goblin",
	&"wolf",
	&"troll",
	&"skeleton_archer",
	&"shadow",
	&"shaman",
]
const EXPECTED_COSTS := [15, 30, 65, 45, 55, 60]


func _init() -> void:
	_run_validation()


func _run_validation() -> void:
	var battle := BATTLE_SCENE.instantiate()
	root.add_child(battle)
	await process_frame
	await process_frame
	var map := battle.get_node("MVPMap")
	var economy := battle.get_node("MonsterEconomy") as MonsterEconomy
	var production := battle.get_node(
		"MonsterProductionManager"
	) as MonsterProductionManager
	var fog := battle.get_node("FogOfWarManager") as FogOfWarManager
	var hud := battle.get_node("HUDLayer/BattleHUD") as Control
	economy.set_process(false)
	economy.add_dark_energy(600, &"t20_validation")
	var nest := map.get_active_nests()[0] as Node2D
	production.select_nest(nest)

	var catalog := production.get_production_catalog()
	if not _validate_catalog(catalog):
		return
	var energy_before := economy.get_dark_energy()
	var monsters: Array[MonsterUnit] = []
	for index in catalog.size():
		if not production.produce(index):
			_fail("A catalog monster could not be produced from the selected nest.")
			return
		var produced := production.get_spawned_monsters()
		var monster := produced[produced.size() - 1] as MonsterUnit
		if monster == null:
			_fail("Production did not instantiate the shared MonsterUnit scene.")
			return
		monsters.append(monster)
		if not _validate_configured_monster(monster, catalog[index], index):
			return
		_disable_combat_and_movement(monster)
	if production.get_spawned_monsters().size() != 6:
		_fail("The selected nest did not produce all six monster types.")
		return
	var total_cost := 0
	for cost in EXPECTED_COSTS:
		total_cost += cost
	if economy.get_dark_energy() != energy_before - total_cost:
		_fail("Producing all six monsters deducted an incorrect total cost.")
		return

	if not _validate_role_differences(catalog, monsters):
		return
	if not await _validate_skeleton_archer_priority(battle, monsters[3]):
		return
	if not _validate_shadow_fog(battle, fog, monsters[4]):
		return
	if not await _validate_shaman_aura(monsters[0], monsters[5]):
		return
	if not _validate_hud(hud, production, catalog):
		return

	print(
		"T20 validation passed: all six data-driven monsters are producible, "
		+ "their costs/stats/roles differ, Skeleton Archer prioritizes buildings, "
		+ "Shadow stealth respects Human fog and targeting, and the visible Shaman "
		+ "aura applies and cleanly removes its ally damage/speed buff."
	)
	quit()


func _validate_catalog(catalog: Array[Resource]) -> bool:
	if catalog.size() != 6:
		_fail("The production catalog must contain exactly six monsters.")
		return false
	for index in catalog.size():
		var data := catalog[index] as MonsterProductionData
		if (
			data == null
			or data.monster_id != EXPECTED_IDS[index]
			or data.cost != EXPECTED_COSTS[index]
			or data.monster_scene == null
		):
			_fail("A monster data resource is missing or ordered incorrectly.")
			return false
	return true


func _validate_configured_monster(
	monster: MonsterUnit, resource: Resource, catalog_index: int
) -> bool:
	var data := resource as MonsterProductionData
	var health := monster.get_node("HealthComponent") as HealthComponent
	var faction := FactionComponent.find_on(monster)
	var melee := monster.get_node("MeleeAttackComponent") as MeleeAttackComponent
	var ranged := monster.get_node(
		"RangedAttackComponent"
	) as RangedAttackComponent
	if (
		monster.get_monster_data() != data
		or monster.get_meta(&"monster_type_id", &"") != EXPECTED_IDS[catalog_index]
		or health.max_health != data.max_health
		or monster.move_speed != data.move_speed
		or faction == null
		or faction.faction != FactionComponent.Faction.MONSTER
	):
		_fail("A produced monster did not receive its Resource stats or faction.")
		return false
	var expects_melee := (
		data.attack_style == MonsterProductionData.AttackStyle.MELEE
	)
	if melee.combat_enabled != expects_melee or ranged.combat_enabled == expects_melee:
		_fail("A produced monster enabled the wrong attack component.")
		return false
	return true


func _validate_role_differences(
	catalog: Array[Resource], monsters: Array[MonsterUnit]
) -> bool:
	var goblin := catalog[0] as MonsterProductionData
	var wolf := catalog[1] as MonsterProductionData
	var troll := catalog[2] as MonsterProductionData
	var archer := catalog[3] as MonsterProductionData
	var shadow := catalog[4] as MonsterProductionData
	var shaman := catalog[5] as MonsterProductionData
	if goblin.cost >= wolf.cost or goblin.max_health >= troll.max_health:
		_fail("Goblin is not the cheap expendable option.")
		return false
	if wolf.move_speed <= goblin.move_speed or wolf.move_speed <= shadow.move_speed:
		_fail("Wolf Beast is not the high-mobility option.")
		return false
	if troll.max_health < 400.0 or troll.move_speed >= goblin.move_speed:
		_fail("Troll is not a clear slow, high-health tank.")
		return false
	if (
		archer.attack_style != MonsterProductionData.AttackStyle.RANGED
		or archer.target_priority != TargetingService.PriorityMode.BUILDINGS_FIRST
	):
		_fail("Skeleton Archer is not configured as a ranged building attacker.")
		return false
	if (
		shadow.special_ability
		!= MonsterProductionData.SpecialAbility.SHORT_STEALTH
		or not monsters[4].is_hidden_from_human()
	):
		_fail("Shadow Stalker did not begin with short stealth.")
		return false
	if (
		shaman.special_ability
		!= MonsterProductionData.SpecialAbility.SUPPORT_AURA
		or shaman.aura_damage_multiplier <= 1.0
		or shaman.aura_speed_multiplier <= 1.0
	):
		_fail("Dark Shaman does not expose a meaningful support aura.")
		return false
	return true


func _validate_skeleton_archer_priority(
	battle: Node2D, archer: MonsterUnit
) -> bool:
	var map := battle.get_node("MVPMap")
	var human_base := map.get("human_base") as Node2D
	var human_unit := _find_living_human_unit()
	if human_base == null or human_unit == null:
		_fail("Could not locate Human targets for Skeleton Archer validation.")
		return false
	archer.global_position = human_base.global_position + Vector2(250.0, 0.0)
	human_unit.global_position = archer.global_position + Vector2(40.0, 0.0)
	archer.get_node("RangedAttackComponent").set("combat_enabled", true)
	await physics_frame
	await physics_frame
	var target := archer.get_node("RangedAttackComponent").call(
		"get_current_target"
	) as Node2D
	archer.get_node("RangedAttackComponent").set("combat_enabled", false)
	if target == null or not target.is_in_group(&"combat_buildings"):
		_fail(
			"Skeleton Archer did not prioritize a building over a nearer unit "
			+ "(priority=%d, target=%s)." % [
				archer.get_node("RangedAttackComponent").get("target_priority"),
				"null" if target == null else str(target.name),
			]
		)
		return false
	return true


func _validate_shadow_fog(
	battle: Node2D, fog: FogOfWarManager, shadow: MonsterUnit
) -> bool:
	var human_unit := _find_living_human_unit()
	if human_unit == null:
		_fail("Could not locate a Human vision source for Shadow validation.")
		return false
	shadow.global_position = human_unit.global_position + Vector2(30.0, 0.0)
	fog.set_human_fog_enabled(true)
	fog.refresh_visibility()
	if shadow.visible or CombatRules.can_damage(human_unit, shadow):
		_fail("A stealthed Shadow leaked through Human fog or targeting.")
		return false
	shadow._process(shadow.get_monster_data().stealth_duration)
	if shadow.is_hidden_from_human():
		_fail("Shadow stealth did not expire after its configured duration.")
		return false
	fog.refresh_visibility()
	if not shadow.visible or not CombatRules.can_damage(human_unit, shadow):
		_fail("An expired Shadow did not return to normal Human visibility.")
		return false
	shadow.global_position = Vector2(1100.0, 620.0)
	fog.refresh_visibility()
	if shadow.visible:
		_fail("Expired stealth bypassed the normal Human fog boundary.")
		return false
	return true


func _validate_shaman_aura(
	goblin: MonsterUnit, shaman: MonsterUnit
) -> bool:
	var goblin_data := goblin.get_monster_data()
	var shaman_data := shaman.get_monster_data()
	goblin.global_position = Vector2(100.0, 400.0)
	shaman.global_position = goblin.global_position + Vector2(40.0, 0.0)
	shaman._process(0.21)
	await process_frame
	var melee := goblin.get_node("MeleeAttackComponent") as MeleeAttackComponent
	if (
		not goblin.is_aura_buffed()
		or not goblin.get_node("BuffIndicator").visible
		or not is_equal_approx(
			melee.attack_damage,
			goblin_data.damage * shaman_data.aura_damage_multiplier
		)
		or not is_equal_approx(
			goblin.move_speed,
			goblin_data.move_speed * shaman_data.aura_speed_multiplier
		)
	):
		_fail("The Shaman aura buff was not visible or did not change ally stats.")
		return false
	shaman.global_position += Vector2(shaman_data.aura_radius + 80.0, 0.0)
	shaman._process(0.21)
	await process_frame
	if (
		goblin.is_aura_buffed()
		or goblin.get_node("BuffIndicator").visible
		or not is_equal_approx(melee.attack_damage, goblin_data.damage)
		or not is_equal_approx(goblin.move_speed, goblin_data.move_speed)
	):
		_fail("Leaving the Shaman aura did not restore the ally's base stats.")
		return false
	shaman.global_position = goblin.global_position + Vector2(40.0, 0.0)
	shaman._process(0.21)
	await process_frame
	if not goblin.is_aura_buffed() or not shaman.get_node("AuraRing").visible:
		_fail("The Shaman aura was not active before the death cleanup check.")
		return false
	var shaman_health := shaman.get_node("HealthComponent") as HealthComponent
	shaman_health.take_damage(shaman_health.current_health, goblin)
	await process_frame
	if (
		shaman.get_node("AuraRing").visible
		or goblin.is_aura_buffed()
		or goblin.get_node("BuffIndicator").visible
		or not is_equal_approx(melee.attack_damage, goblin_data.damage)
		or not is_equal_approx(goblin.move_speed, goblin_data.move_speed)
	):
		_fail("A dead Shaman left its aura art or ally buff active.")
		return false
	return true


func _validate_hud(
	hud: Control,
	production: MonsterProductionManager,
	catalog: Array[Resource]
) -> bool:
	var panel := hud.get_node("MonsterProductionPanel") as ColorRect
	var button_names := [
		"MonsterTypeZeroButton",
		"MonsterTypeOneButton",
		"MonsterTypeTwoButton",
		"MonsterTypeThreeButton",
		"MonsterTypeFourButton",
		"MonsterTypeFiveButton",
	]
	if not panel.visible:
		_fail("Selecting a nest did not open the six-monster production panel.")
		return false
	for index in button_names.size():
		var button := panel.get_node(button_names[index]) as Button
		var data := catalog[index] as MonsterProductionData
		if (
			button == null
			or not button.visible
			or data.display_name.to_upper() not in button.text
			or str(production.get_effective_cost(index)) + " DARK" not in button.text
			or button.tooltip_text != data.role_description
		):
			_fail("The HUD did not expose one of the six data-driven monsters.")
			return false
	return true


func _find_living_human_unit() -> Node2D:
	for candidate in get_nodes_in_group(&"combat_units"):
		if not candidate is Node2D:
			continue
		var faction := FactionComponent.find_on(candidate)
		var health := candidate.get_node_or_null(
			"HealthComponent"
		) as HealthComponent
		if (
			faction != null
			and faction.faction == FactionComponent.Faction.HUMAN
			and health != null
			and not health.is_dead
		):
			return candidate as Node2D
	return null


func _disable_combat_and_movement(monster: MonsterUnit) -> void:
	monster.set_physics_process(false)
	monster.get_node("MeleeAttackComponent").set("combat_enabled", false)
	monster.get_node("RangedAttackComponent").set("combat_enabled", false)


func _fail(message: String) -> void:
	push_error("T20 validation failed: %s" % message)
	quit(1)
