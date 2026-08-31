extends SceneTree

const HUMAN_UNIT_SCENE := preload("res://units/placeholders/test_unit.tscn")
const MONSTER_UNIT_SCENE := preload("res://units/placeholders/test_monster.tscn")
const HUMAN_BASE_SCENE := preload("res://buildings/placeholders/human_base_placeholder.tscn")
const MONSTER_NEST_SCENE := preload("res://buildings/placeholders/monster_nest_placeholder.tscn")


func _init() -> void:
	_run_validation()


func _run_validation() -> void:
	var human_a := HUMAN_UNIT_SCENE.instantiate()
	var human_b := HUMAN_UNIT_SCENE.instantiate()
	var monster_a := MONSTER_UNIT_SCENE.instantiate()
	var monster_b := MONSTER_UNIT_SCENE.instantiate()
	var human_base := HUMAN_BASE_SCENE.instantiate()
	var monster_nest := MONSTER_NEST_SCENE.instantiate()

	var actors := [
		human_a,
		human_b,
		monster_a,
		monster_b,
		human_base,
		monster_nest,
	]
	for actor in actors:
		root.add_child(actor)
	await process_frame

	human_a.position = Vector2.ZERO
	human_b.position = Vector2.ZERO
	monster_a.position = Vector2.ZERO
	monster_b.position = Vector2.ZERO

	if _get_faction(human_a) != FactionComponent.Faction.HUMAN:
		_fail("Human unit does not have the Human faction.")
		return
	if _get_faction(human_base) != FactionComponent.Faction.HUMAN:
		_fail("Human base does not have the Human faction.")
		return
	if _get_faction(monster_a) != FactionComponent.Faction.MONSTER:
		_fail("Monster unit does not have the Monster faction.")
		return
	if _get_faction(monster_nest) != FactionComponent.Faction.MONSTER:
		_fail("Monster nest does not have the Monster faction.")
		return

	if not CombatRules.are_allies(human_a, human_b):
		_fail("Two Human units were not recognized as allies.")
		return
	if not CombatRules.are_allies(monster_a, monster_b):
		_fail("Two Monster units were not recognized as allies.")
		return
	if CombatRules.are_allies(human_a, monster_a):
		_fail("Human and Monster units were incorrectly recognized as allies.")
		return

	var human_b_health := _get_health(human_b)
	var human_b_before: float = human_b_health.current_health
	var friendly_human_damage := CombatRules.try_apply_damage(
		human_a, human_b, 25.0
	)
	if not is_zero_approx(friendly_human_damage):
		_fail("Human unit applied friendly fire to another Human.")
		return
	if not is_equal_approx(human_b_health.current_health, human_b_before):
		_fail("Overlapping Human units changed friendly health.")
		return

	var monster_b_health := _get_health(monster_b)
	var monster_b_before: float = monster_b_health.current_health
	var friendly_monster_damage := CombatRules.try_apply_damage(
		monster_a, monster_b, 25.0
	)
	if not is_zero_approx(friendly_monster_damage):
		_fail("Monster unit applied friendly fire to another Monster.")
		return
	if not is_equal_approx(monster_b_health.current_health, monster_b_before):
		_fail("Overlapping Monster units changed friendly health.")
		return

	var monster_a_health := _get_health(monster_a)
	var human_to_monster := CombatRules.try_apply_damage(
		human_a, monster_a, 30.0
	)
	if not is_equal_approx(human_to_monster, 30.0):
		_fail("Human unit could not damage a Monster.")
		return
	if not is_equal_approx(monster_a_health.current_health, 90.0):
		_fail("Monster health did not change after hostile Human damage.")
		return

	var human_a_health := _get_health(human_a)
	var monster_to_human := CombatRules.try_apply_damage(
		monster_a, human_a, 20.0
	)
	if not is_equal_approx(monster_to_human, 20.0):
		_fail("Monster unit could not damage a Human.")
		return
	if not is_equal_approx(human_a_health.current_health, 80.0):
		_fail("Human health did not change after hostile Monster damage.")
		return

	if not is_equal_approx(
		CombatRules.try_apply_damage(human_a, monster_nest, 10.0),
		10.0
	):
		_fail("Human faction could not damage a Monster building.")
		return
	if not is_equal_approx(
		CombatRules.try_apply_damage(monster_nest, human_base, 10.0),
		10.0
	):
		_fail("Monster faction could not damage a Human building.")
		return

	var neutral_actor := Node2D.new()
	root.add_child(neutral_actor)
	if CombatRules.can_damage(neutral_actor, human_a):
		_fail("Actor without a faction was allowed to damage a target.")
		return
	if CombatRules.can_damage(human_a, neutral_actor):
		_fail("Actor without a faction was accepted as a hostile target.")
		return

	print(
		"T05 validation passed: Human/Monster identity, hostile damage, "
		+ "and friendly-fire rejection for overlapping units and buildings."
	)
	quit()


func _get_faction(actor: Node) -> FactionComponent.Faction:
	var component := FactionComponent.find_on(actor)
	return component.faction


func _get_health(actor: Node) -> HealthComponent:
	return actor.get_node("HealthComponent") as HealthComponent


func _fail(message: String) -> void:
	push_error("T05 validation failed: %s" % message)
	quit(1)
