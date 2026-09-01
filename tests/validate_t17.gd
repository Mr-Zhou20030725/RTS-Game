extends SceneTree

const MAP_SCENE := preload("res://scenes/map/mvp_map.tscn")
const MONSTER_ECONOMY_SCENE := preload(
	"res://scenes/economy/monster_economy.tscn"
)
const HUMAN_SCENE := preload("res://units/placeholders/test_unit.tscn")
const MONSTER_SCENE := preload("res://units/placeholders/test_monster.tscn")
const TOWER_SCENE := preload("res://buildings/towers/defense_tower.tscn")
const BATTLE_SCENE := preload("res://scenes/battle/battle.tscn")

var rejected_spend_count := 0
var kill_reward_count := 0
var kill_reward_total := 0


func _init() -> void:
	_run_validation()


func _run_validation() -> void:
	if not await _validate_income_spending_and_rewards():
		return
	if not await _validate_battle_hud():
		return
	print(
		"T17 validation passed: four nests produce stable dark energy, income "
		+ "tracks nest losses, Monster production spending is exact and safe, "
		+ "Human unit/tower kills grant configured rewards, and the HUD stays synced."
	)
	quit()


func _validate_income_spending_and_rewards() -> bool:
	var map := MAP_SCENE.instantiate()
	map.generation_seed = 3
	var economy := MONSTER_ECONOMY_SCENE.instantiate() as MonsterEconomy
	economy.starting_dark_energy = 30
	economy.energy_per_nest = 3
	economy.income_interval = 1.0
	economy.human_unit_kill_reward = 7
	economy.human_tower_kill_reward = 11
	economy.spend_rejected.connect(_on_spend_rejected)
	economy.kill_reward_granted.connect(_on_kill_reward_granted)
	root.add_child(map)
	root.add_child(economy)
	await process_frame
	await process_frame
	economy.set_process(false)

	if (
		economy.get_dark_energy() != 30
		or economy.get_active_nest_count() != 4
		or economy.get_income_per_interval() != 12
	):
		_fail("MonsterEconomy did not initialize from four active nests.")
		return false
	economy._process(1.0)
	if economy.get_dark_energy() != 42:
		_fail("Four nests did not produce their exact configured income.")
		return false

	var destroyed_nest := map.get_active_nests()[0] as Node2D
	var nest_health := destroyed_nest.get_node(
		"HealthComponent"
	) as HealthComponent
	nest_health.take_damage(nest_health.max_health)
	await process_frame
	if (
		economy.get_active_nest_count() != 3
		or economy.get_income_per_interval() != 9
	):
		_fail("Dark energy income did not update after a nest was destroyed.")
		return false
	economy._process(1.0)
	if economy.get_dark_energy() != 51:
		_fail("Three remaining nests produced an incorrect income amount.")
		return false

	if not economy.try_spend(20, &"monster_production"):
		_fail("Affordable Monster production spending was rejected.")
		return false
	if economy.get_dark_energy() != 31:
		_fail("Monster production did not deduct its exact dark energy cost.")
		return false
	if economy.try_spend(50, &"monster_production"):
		_fail("Unaffordable Monster production spending was accepted.")
		return false
	if economy.get_dark_energy() != 31 or rejected_spend_count != 1:
		_fail("Rejected spending changed energy or emitted the wrong result.")
		return false

	var monster := MONSTER_SCENE.instantiate() as Node2D
	var human := HUMAN_SCENE.instantiate() as Node2D
	var tower := TOWER_SCENE.instantiate() as Node2D
	monster.get_node("MeleeAttackComponent").set("combat_enabled", false)
	human.get_node("MeleeAttackComponent").set("combat_enabled", false)
	tower.add_to_group(&"placed_towers")
	root.add_child(monster)
	root.add_child(human)
	root.add_child(tower)
	await process_frame
	CombatRules.try_apply_damage(monster, human, 100000.0)
	CombatRules.try_apply_damage(monster, tower, 100000.0)
	if (
		economy.get_dark_energy() != 49
		or kill_reward_count != 2
		or kill_reward_total != 18
	):
		_fail("Human unit and tower kills did not grant configured rewards.")
		return false

	_cleanup([map, economy, monster, human, tower])
	await process_frame
	return true


func _validate_battle_hud() -> bool:
	var battle := BATTLE_SCENE.instantiate()
	root.add_child(battle)
	await process_frame
	await process_frame
	var economy := battle.get_node("MonsterEconomy") as MonsterEconomy
	var hud := battle.get_node("HUDLayer/BattleHUD") as Control
	var energy_label := hud.get_node("TopBar/DarkEnergyLabel") as Label
	var rate_label := hud.get_node("TopBar/DarkEnergyRateLabel") as Label
	if (
		economy == null
		or energy_label == null
		or rate_label == null
		or not energy_label.is_visible_in_tree()
		or not rate_label.is_visible_in_tree()
	):
		_fail("Battle did not expose the active MonsterEconomy HUD labels.")
		return false
	if energy_label.text != "DARK: 40" or "4 nests" not in rate_label.text:
		_fail("Dark energy HUD did not show the starting balance and four-nest rate.")
		return false
	var viewport_rect := Rect2(Vector2.ZERO, hud.get_viewport_rect().size)
	if (
		not viewport_rect.intersects(energy_label.get_global_rect())
		or not viewport_rect.intersects(rate_label.get_global_rect())
	):
		_fail("Dark energy HUD labels are outside the visible viewport.")
		return false
	economy.add_dark_energy(5, &"test_reward")
	if energy_label.text != "DARK: 45":
		_fail("Dark energy HUD did not follow balance changes.")
		return false
	var map := battle.get_node("MVPMap")
	var nest := map.get_active_nests()[0] as Node2D
	var health := nest.get_node("HealthComponent") as HealthComponent
	health.take_damage(health.max_health)
	await process_frame
	if "3 nests" not in rate_label.text:
		_fail("Dark energy HUD rate did not follow the active nest count.")
		return false

	_cleanup([battle])
	await process_frame
	return true


func _on_spend_rejected(_cost: int, _current_energy: int) -> void:
	rejected_spend_count += 1


func _on_kill_reward_granted(_victim: Node, amount: int) -> void:
	kill_reward_count += 1
	kill_reward_total += amount


func _cleanup(nodes: Array) -> void:
	for node in nodes:
		if node != null and is_instance_valid(node):
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.queue_free()


func _fail(message: String) -> void:
	push_error("T17 validation failed: %s" % message)
	quit(1)
