extends SceneTree

const ECONOMY_SCENE := preload("res://scenes/economy/human_economy.tscn")
const HUD_SCENE := preload("res://ui/battle_hud/battle_hud.tscn")
const HUMAN_SCENE := preload("res://units/placeholders/test_unit.tscn")
const MONSTER_SCENE := preload("res://units/placeholders/test_monster.tscn")

var change_reasons: Array[StringName] = []
var reward_event_count := 0


func _init() -> void:
	_run_validation()


func _run_validation() -> void:
	var economy = ECONOMY_SCENE.instantiate()
	economy.starting_gold = 120
	economy.passive_income_amount = 7
	economy.passive_income_interval = 0.05
	economy.monster_kill_reward = 30
	economy.gold_changed.connect(_on_gold_changed)
	economy.kill_reward_granted.connect(_on_kill_reward_granted)
	root.add_child(economy)
	await process_frame

	if economy.get_gold() != 120:
		_fail("HumanEconomy did not initialize with configured starting gold.")
		return

	await create_timer(0.14).timeout
	var passive_gain: int = economy.get_gold() - 120
	if passive_gain < 14 or passive_gain % 7 != 0:
		_fail("Passive gold did not increase by the configured rule.")
		return
	if not change_reasons.has(&"passive_income"):
		_fail("Passive income did not report its transaction reason.")
		return

	economy.passive_income_amount = 0
	var balance_before_rejection: int = economy.get_gold()
	if economy.try_spend(balance_before_rejection + 1, &"test"):
		_fail("Economy accepted a purchase above the current balance.")
		return
	if economy.get_gold() != balance_before_rejection:
		_fail("Rejected purchase changed the gold balance.")
		return
	if economy.try_spend(-1, &"test"):
		_fail("Economy accepted a negative purchase cost.")
		return
	if not economy.try_spend(20, &"test"):
		_fail("Economy rejected an affordable purchase.")
		return
	if economy.get_gold() != balance_before_rejection - 20:
		_fail("Affordable purchase deducted the wrong amount.")
		return
	if not economy.try_spend(economy.get_gold(), &"test"):
		_fail("Economy could not spend its exact remaining balance.")
		return
	if economy.get_gold() != 0:
		_fail("Spending the exact balance did not stop at zero.")
		return
	if economy.try_spend(1, &"test") or economy.get_gold() < 0:
		_fail("Gold became negative after an insufficient purchase.")
		return

	economy.add_gold(50, &"test_setup")
	var human := HUMAN_SCENE.instantiate()
	var monster := MONSTER_SCENE.instantiate()
	_set_combat_enabled(human, false)
	_set_combat_enabled(monster, false)
	root.add_child(human)
	root.add_child(monster)
	await process_frame

	var before_reward: int = economy.get_gold()
	CombatRules.try_apply_damage(human, monster, 100000.0)
	await process_frame
	if economy.get_gold() != before_reward + 30:
		_fail("Human kill did not grant the configured Monster reward.")
		return
	if reward_event_count != 1:
		_fail("Monster kill reward was not emitted exactly once.")
		return
	CombatRules.try_apply_damage(human, monster, 100000.0)
	if economy.get_gold() != before_reward + 30:
		_fail("Dead Monster granted its kill reward more than once.")
		return

	var hud := HUD_SCENE.instantiate()
	root.add_child(hud)
	await process_frame
	await process_frame
	var gold_label := hud.get_node("TopBar/GoldLabel") as Label
	if gold_label.text != "GOLD: %d" % economy.get_gold():
		_fail("Battle HUD did not display the current Human gold.")
		return

	var before_hud_spend: int = economy.get_gold()
	(hud.get_node("TopBar/SpendTestButton") as Button).pressed.emit()
	if economy.get_gold() != before_hud_spend - 50:
		_fail("T09 HUD test button did not use validated economy spending.")
		return
	if gold_label.text != "GOLD: %d" % economy.get_gold():
		_fail("HUD gold display did not update after spending.")
		return

	print(
		"T09 validation passed: starting/passive gold, Human kill rewards, "
		+ "safe spending, non-negative balance, and HUD synchronization."
	)
	quit()


func _set_combat_enabled(actor: Node, enabled: bool) -> void:
	for component_name in ["MeleeAttackComponent", "RangedAttackComponent"]:
		var component := actor.get_node_or_null(component_name)
		if component != null:
			component.set("combat_enabled", enabled)


func _on_gold_changed(
	_current_gold: int, _change: int, reason: StringName
) -> void:
	change_reasons.append(reason)


func _on_kill_reward_granted(_victim: Node, _amount: int) -> void:
	reward_event_count += 1


func _fail(message: String) -> void:
	push_error("T09 validation failed: %s" % message)
	quit(1)
