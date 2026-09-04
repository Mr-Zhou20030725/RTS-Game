extends SceneTree

const BATTLE_SCENE := preload("res://scenes/battle/battle.tscn")


func _init() -> void:
	_run_validation()


func _run_validation() -> void:
	var battle := BATTLE_SCENE.instantiate()
	root.add_child(battle)
	await process_frame
	await process_frame
	await process_frame
	var effects := battle.get_node("EventEffectManager") as EventEffectManager
	var time_manager := battle.get_node("GameTimeManager") as GameTimeManager
	var human_economy := battle.get_node("HumanEconomy") as HumanEconomy
	var monster_economy := battle.get_node("MonsterEconomy") as MonsterEconomy
	var production := battle.get_node(
		"MonsterProductionManager"
	) as MonsterProductionManager
	var placement := battle.get_node(
		"BuildingPlacementManager"
	) as BuildingPlacementManager
	var fog := battle.get_node("FogOfWarManager") as FogOfWarManager
	battle.get_node("HumanAIController").call("set_ai_enabled", false)
	battle.get_node("MonsterAIController").call("set_ai_enabled", false)
	time_manager.set_process(false)
	human_economy.set_process(false)
	monster_economy.set_process(false)
	effects.set_process(false)
	effects.configure_dependencies(production, monster_economy, fog)

	if (
		effects.config.cards.size() != 10
		or effects.config.get_cards_for_round(1).size() != 5
		or effects.config.get_cards_for_round(2).size() != 5
	):
		_fail("Event deck is not split into two rounds of five real cards.")
		return

	human_economy.add_gold(1000, &"t29_setup")
	var base := battle.get_node("MVPMap").get("human_base") as Node2D
	var tower := placement.place_tower_at(
		0, base.global_position + Vector2(220.0, 0.0)
	) as DefenseTower
	var human_unit := _find_unit(FactionComponent.Faction.HUMAN)
	monster_economy.add_dark_energy(1000, &"t29_setup")
	var nests: Array[Node2D] = battle.get_node("MVPMap").call(
		"get_active_nests"
	)
	if (
		tower == null
		or human_unit == null
		or nests.is_empty()
		or not production.produce_from_nest(0, nests[0])
	):
		_fail("Could not prepare tower and faction units for effect validation.")
		return
	var monsters := production.get_spawned_monsters()
	var monster := monsters[monsters.size() - 1] as MonsterUnit
	var tower_attack := tower.get_node("RangedAttackComponent")
	var tower_interval := float(tower_attack.attack_interval)
	var tower_range := float(tower_attack.attack_range)
	var human_melee := human_unit.get_node_or_null("MeleeAttackComponent")
	var human_ranged := human_unit.get_node_or_null("RangedAttackComponent")
	var human_damage := _get_active_damage(human_melee, human_ranged)
	var human_speed := float(human_unit.get("move_speed"))
	var monster_damage := monster.get_current_damage_multiplier()
	var monster_speed := monster.get_current_speed_multiplier()

	var tower_haste := _card(effects, &"human_arcane_overload")
	effects.activate_card(tower_haste, FactionComponent.Faction.HUMAN)
	effects.activate_card(tower_haste, FactionComponent.Faction.HUMAN)
	if (
		not is_equal_approx(tower_attack.attack_interval, tower_interval * 0.6)
		or not is_equal_approx(effects.get_effect_remaining(tower_haste.event_id), 45.0)
	):
		_fail("Tower haste stacked permanently instead of refreshing.")
		return
	effects.advance_effect_time(45.0)
	if not is_equal_approx(tower_attack.attack_interval, tower_interval):
		_fail("Tower haste did not restore attack interval.")
		return

	var rally := _card(effects, &"human_battle_rally")
	effects.activate_card(rally, FactionComponent.Faction.HUMAN)
	effects.activate_card(rally, FactionComponent.Faction.HUMAN)
	if (
		not is_equal_approx(
			_get_active_damage(human_melee, human_ranged), human_damage * 1.3
		)
		or not is_equal_approx(
			float(human_unit.get("move_speed")), human_speed * 1.15
		)
	):
		_fail("Human rally did not apply once to damage and speed.")
		return
	effects.advance_effect_time(45.0)
	if (
		not is_equal_approx(
			_get_active_damage(human_melee, human_ranged), human_damage
		)
		or not is_equal_approx(float(human_unit.get("move_speed")), human_speed)
	):
		_fail("Human rally stats did not restore.")
		return

	var bloodmoon := _card(effects, &"monster_bloodmoon")
	var base_goblin_cost := production.get_effective_cost(0)
	effects.activate_card(bloodmoon, FactionComponent.Faction.MONSTER)
	if production.get_effective_cost(0) != roundi(base_goblin_cost * 0.65):
		_fail("Blood Moon did not reduce monster production cost.")
		return
	effects.advance_effect_time(45.0)
	if production.get_effective_cost(0) != base_goblin_cost:
		_fail("Blood Moon production cost did not restore.")
		return

	var war_drums := _card(effects, &"monster_war_drums")
	effects.activate_card(war_drums, FactionComponent.Faction.MONSTER)
	effects.activate_card(war_drums, FactionComponent.Faction.MONSTER)
	if (
		not is_equal_approx(monster.get_current_damage_multiplier(), 1.3)
		or not is_equal_approx(monster.get_current_speed_multiplier(), 1.2)
	):
		_fail("Monster war drums stacked or failed to apply.")
		return
	effects.advance_effect_time(45.0)
	if (
		not is_equal_approx(monster.get_current_damage_multiplier(), monster_damage)
		or not is_equal_approx(monster.get_current_speed_multiplier(), monster_speed)
	):
		_fail("Monster war drums did not restore.")
		return

	var eclipse := _card(effects, &"neutral_ancient_relic")
	fog.set_human_fog_enabled(true)
	effects.activate_card(eclipse, FactionComponent.Faction.HUMAN)
	if fog.is_human_fog_enabled():
		_fail("Human Eclipse did not reveal the battlefield.")
		return
	effects.advance_effect_time(35.0)
	if not fog.is_human_fog_enabled():
		_fail("Human Eclipse did not restore fog.")
		return
	effects.activate_card(eclipse, FactionComponent.Faction.MONSTER)
	if not is_equal_approx(tower_attack.attack_range, tower_range * 0.7):
		_fail("Monster Eclipse did not reduce tower range.")
		return
	effects.advance_effect_time(35.0)
	if not is_equal_approx(tower_attack.attack_range, tower_range):
		_fail("Monster Eclipse did not restore tower range.")
		return

	var tower_health := tower.get_node("HealthComponent") as HealthComponent
	tower_health.take_damage(100.0)
	var damaged_health := tower_health.current_health
	effects.activate_card(
		_card(effects, &"human_emergency_repair"),
		FactionComponent.Faction.HUMAN
	)
	if tower_health.current_health <= damaged_health:
		_fail("Emergency Repair did not heal Human buildings.")
		return

	var vision := human_unit.get_node("VisionSourceComponent") as VisionSourceComponent
	var base_vision := vision.get_vision_radius()
	var eagle_eye := _card(effects, &"human_eagle_eye")
	effects.activate_card(eagle_eye, FactionComponent.Faction.HUMAN)
	effects.activate_card(eagle_eye, FactionComponent.Faction.HUMAN)
	if not is_equal_approx(vision.get_vision_radius(), base_vision * 1.5):
		_fail("Eagle Eye stacked or failed to expand vision.")
		return
	effects.advance_effect_time(60.0)
	if not is_equal_approx(vision.get_vision_radius(), base_vision):
		_fail("Eagle Eye vision did not restore.")
		return

	var income_base := monster_economy.get_nest_income_multiplier()
	var dark_surge := _card(effects, &"monster_dark_surge")
	effects.activate_card(dark_surge, FactionComponent.Faction.MONSTER)
	effects.activate_card(dark_surge, FactionComponent.Faction.MONSTER)
	if not is_equal_approx(
		monster_economy.get_nest_income_multiplier(), income_base * 1.6
	):
		_fail("Dark Surge stacked or failed to increase income.")
		return
	effects.advance_effect_time(60.0)
	if not is_equal_approx(
		monster_economy.get_nest_income_multiplier(), income_base
	):
		_fail("Dark Surge income did not restore.")
		return

	var goblin_raid := _card(effects, &"monster_goblin_raid")
	var other_cost := production.get_effective_cost(1)
	effects.activate_card(goblin_raid, FactionComponent.Faction.MONSTER)
	effects.activate_card(goblin_raid, FactionComponent.Faction.MONSTER)
	if (
		production.get_effective_cost(0) != roundi(base_goblin_cost * 0.45)
		or production.get_effective_cost(1) != other_cost
	):
		_fail("Goblin Raid did not exclusively discount Goblins.")
		return
	effects.advance_effect_time(60.0)
	if production.get_effective_cost(0) != base_goblin_cost:
		_fail("Goblin Raid cost did not restore.")
		return

	var magic_storm := _card(effects, &"neutral_magic_storm")
	effects.activate_card(magic_storm, FactionComponent.Faction.HUMAN)
	if not tower.is_upgraded():
		_fail("Human Magic Storm did not grant a free tower upgrade.")
		return
	var energy_before_storm := monster_economy.get_dark_energy()
	effects.activate_card(magic_storm, FactionComponent.Faction.MONSTER)
	if monster_economy.get_dark_energy() != energy_before_storm + 120:
		_fail("Monster Magic Storm did not grant dark energy.")
		return

	var auction := battle.get_node(
		"EventAuctionManager"
	) as EventAuctionManager
	time_manager.jump_to_time(300.0)
	var first_round_bid := human_economy.get_gold()
	if (
		not auction.is_auction_active()
		or not auction.submit_player_bid(first_round_bid)
		or effects.get_active_effect_count() != 5
	):
		_fail("Round-one auction did not activate all five real card effects.")
		return
	auction.finish_auction()
	effects.advance_effect_time(60.0)
	if effects.get_active_effect_count() != 0:
		_fail("Round-one auction effects did not all expire.")
		return

	time_manager.jump_to_time(900.0)
	var round_two_card := auction.get_node(
		"Overlay/AuctionPanel/Content/HumanCardOne/CardLabel"
	) as Label
	if (
		not auction.is_auction_active()
		or not "紧急修复" in round_two_card.text
		or not auction.submit_player_bid(0)
		or effects.get_active_effect_count() != 3
	):
		_fail("Round-two auction did not switch cards or activate its effects.")
		return
	auction.finish_auction()
	effects.advance_effect_time(60.0)

	print(
		"T29 validation passed: all ten cards apply real effects, timed "
		+ "effects restore their systems, and repeated buffs refresh "
		+ "without permanent multiplication."
	)
	quit()


func _card(
	effects: EventEffectManager, event_id: StringName
) -> AuctionEventCardData:
	for card in effects.config.cards:
		if card.event_id == event_id:
			return card
	return null


func _find_unit(faction_value: FactionComponent.Faction) -> Node2D:
	for node in get_nodes_in_group(&"combat_units"):
		var unit := node as Node2D
		var faction := FactionComponent.find_on(unit)
		if faction != null and faction.faction == faction_value:
			return unit
	return null


func _get_active_damage(melee: Node, ranged: Node) -> float:
	if melee != null and bool(melee.get("combat_enabled")):
		return float(melee.get("attack_damage"))
	if ranged != null:
		return float(ranged.get("attack_damage"))
	return 0.0


func _fail(message: String) -> void:
	paused = false
	push_error("T29 validation failed: %s" % message)
	quit(1)
