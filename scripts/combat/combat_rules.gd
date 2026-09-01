class_name CombatRules
extends RefCounted

## Central gate for all faction-aware targeting and damage.


static func are_allies(first_actor: Node, second_actor: Node) -> bool:
	var first_faction := FactionComponent.find_on(first_actor)
	var second_faction := FactionComponent.find_on(second_actor)
	if first_faction == null or second_faction == null:
		return false
	return first_faction.is_same_faction(second_faction)


static func can_damage(attacker: Node, target: Node) -> bool:
	if attacker == null or target == null or attacker == target:
		return false

	var attacker_faction := FactionComponent.find_on(attacker)
	var target_faction := FactionComponent.find_on(target)
	if attacker_faction == null or target_faction == null:
		return false
	var attacker_health := attacker.get_node_or_null(
		"HealthComponent"
	) as HealthComponent
	var target_health := target.get_node_or_null(
		"HealthComponent"
	) as HealthComponent
	if attacker_health != null and attacker_health.is_dead:
		return false
	if target_health != null and target_health.is_dead:
		return false
	if not _passes_human_visibility(attacker, target):
		return false
	return attacker_faction.is_hostile_to(target_faction)


static func _passes_human_visibility(attacker: Node, target: Node) -> bool:
	var attacker_faction := FactionComponent.find_on(attacker)
	var target_faction := FactionComponent.find_on(target)
	if (
		attacker_faction == null
		or target_faction == null
		or attacker_faction.faction != FactionComponent.Faction.HUMAN
		or target_faction.faction != FactionComponent.Faction.MONSTER
	):
		return true
	if not attacker.is_inside_tree():
		return true
	var fog_manager := attacker.get_tree().get_first_node_in_group(
		&"human_fog_manager"
	)
	return (
		fog_manager == null
		or not fog_manager.call("is_human_fog_enabled")
		or fog_manager.call("is_node_visible_to_human", target)
	)


static func try_apply_damage(
	attacker: Node, target: Node, amount: float
) -> float:
	if amount <= 0.0 or not can_damage(attacker, target):
		return 0.0

	var health_component := target.get_node_or_null("HealthComponent") as HealthComponent
	if health_component == null:
		return 0.0
	return health_component.take_damage(amount, attacker)
