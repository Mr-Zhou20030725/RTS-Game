extends SceneTree

const ECONOMY_SCENE := preload("res://scenes/economy/human_economy.tscn")
const PLACEMENT_SCENE := preload(
	"res://scenes/building/building_placement_manager.tscn"
)
const HUD_SCENE := preload("res://ui/battle_hud/battle_hud.tscn")


func _init() -> void:
	_run_validation()


func _run_validation() -> void:
	if not await _validate_four_one_time_upgrades():
		return
	if not await _validate_insufficient_gold_rejected():
		return
	print(
		"T12 validation passed: placed towers can be selected and upgraded once, "
		+ "configured combat stats change, exact gold is spent, and insufficient "
		+ "or repeated upgrades are rejected."
	)
	quit()


func _validate_four_one_time_upgrades() -> bool:
	var economy = ECONOMY_SCENE.instantiate()
	economy.starting_gold = 1000
	economy.passive_income_amount = 0
	var placement = PLACEMENT_SCENE.instantiate()
	var hud := HUD_SCENE.instantiate()
	root.add_child(economy)
	root.add_child(placement)
	root.add_child(hud)
	await process_frame
	await process_frame

	var positions := [
		Vector2(160, 160), Vector2(320, 160),
		Vector2(480, 160), Vector2(640, 160),
	]
	var expected_total_upgrade_cost := 0
	for index in 4:
		if not placement.begin_tower_placement(index, positions[index]):
			_fail("Could not begin placement for tower index %d." % index)
			return false
		if not placement.confirm_placement():
			_fail("Could not place tower index %d for upgrade testing." % index)
			return false

	var towers: Array[Node2D] = placement.get_placed_buildings()
	if towers.size() != 4:
		_fail("Upgrade test did not create four placed towers.")
		return false

	for index in 4:
		var tower := towers[index]
		var data = tower.call("get_tower_data")
		var ranged = tower.get_node("RangedAttackComponent")
		var gold_before: int = economy.get_gold()
		var cost: int = tower.call("get_upgrade_cost")
		expected_total_upgrade_cost += cost

		if not placement.select_tower_at(positions[index] + Vector2(4, 3)):
			_fail("Click-position selection failed for tower index %d." % index)
			return false
		if placement.get_selected_tower() != tower:
			_fail("Placement manager selected the wrong tower.")
			return false
		if index == 0:
			var upgrade_button := hud.get_node(
				"TowerBuildBar/UpgradeTowerButton"
			) as Button
			if upgrade_button.disabled:
				_fail("HUD upgrade button stayed disabled after tower selection.")
				return false
			upgrade_button.pressed.emit()
		else:
			if not placement.upgrade_selected_tower():
				_fail("Affordable tower index %d could not be upgraded." % index)
				return false

		if not tower.call("is_upgraded"):
			_fail("Tower index %d did not enter its level 2 state." % index)
			return false
		if economy.get_gold() != gold_before - cost:
			_fail("Tower upgrade did not deduct its exact configured cost.")
			return false
		if not is_equal_approx(
			ranged.attack_damage,
			float(data.get("damage")) * float(data.get("upgrade_damage_multiplier"))
		):
			_fail("Upgraded damage did not match TowerData.")
			return false
		if not is_equal_approx(
			ranged.attack_range,
			float(data.get("attack_range")) + float(data.get("upgrade_range_bonus"))
		):
			_fail("Upgraded range did not match TowerData.")
			return false
		if not is_equal_approx(
			ranged.attack_interval,
			float(data.get("attack_interval"))
			* float(data.get("upgrade_attack_interval_multiplier"))
		):
			_fail("Upgraded attack interval did not match TowerData.")
			return false

		var gold_after_upgrade: int = economy.get_gold()
		if placement.upgrade_selected_tower():
			_fail("Tower index %d accepted a repeated upgrade." % index)
			return false
		if economy.get_gold() != gold_after_upgrade:
			_fail("Rejected repeated upgrade deducted gold.")
			return false

	if expected_total_upgrade_cost <= 0:
		_fail("Tower upgrade costs are not data-configured.")
		return false
	if placement.select_tower_at(Vector2(1000, 600)):
		_fail("Clicking empty terrain retained a selected tower.")
		return false
	if not (hud.get_node("TowerBuildBar/UpgradeTowerButton") as Button).disabled:
		_fail("HUD upgrade button stayed enabled with no selected tower.")
		return false

	_cleanup([economy, placement, hud])
	await process_frame
	return true


func _validate_insufficient_gold_rejected() -> bool:
	var economy = ECONOMY_SCENE.instantiate()
	economy.starting_gold = 50
	economy.passive_income_amount = 0
	var placement = PLACEMENT_SCENE.instantiate()
	root.add_child(economy)
	root.add_child(placement)
	await process_frame

	var position := Vector2(240, 240)
	if not placement.begin_tower_placement(0, position):
		_fail("Could not place the affordable setup tower.")
		return false
	if not placement.confirm_placement():
		_fail("Could not confirm the insufficient-gold setup tower.")
		return false
	var tower: Node2D = placement.get_placed_buildings()[0]
	var ranged = tower.get_node("RangedAttackComponent")
	var damage_before: float = ranged.attack_damage
	placement.select_tower(tower)
	if placement.upgrade_selected_tower():
		_fail("Upgrade succeeded with zero remaining gold.")
		return false
	if (
		economy.get_gold() != 0
		or tower.call("is_upgraded")
		or not is_equal_approx(ranged.attack_damage, damage_before)
	):
		_fail("Rejected unaffordable upgrade changed gold or tower stats.")
		return false

	_cleanup([economy, placement])
	await process_frame
	return true


func _cleanup(nodes: Array) -> void:
	for node in nodes:
		if node != null and is_instance_valid(node):
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.queue_free()


func _fail(message: String) -> void:
	push_error("T12 validation failed: %s" % message)
	quit(1)
