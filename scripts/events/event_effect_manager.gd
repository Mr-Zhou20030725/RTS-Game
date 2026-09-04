class_name EventEffectManager
extends Node

signal effect_started(
	event_id: StringName,
	faction: FactionComponent.Faction,
	duration: float
)
signal effect_expired(event_id: StringName)

@export var config: EventAuctionConfig

var monster_production: MonsterProductionManager
var monster_economy: MonsterEconomy
var fog_manager: FogOfWarManager
var _active_effects: Dictionary = {}
var _saved_fog_states: Dictionary = {}
var _refresh_elapsed := 0.0
@onready var status_panel: PanelContainer = get_node_or_null(
	"StatusLayer/StatusPanel"
)
@onready var status_label: Label = get_node_or_null(
	"StatusLayer/StatusPanel/StatusLabel"
)


func _ready() -> void:
	call_deferred("_bind_dependencies")
	_update_status_display()


func _process(delta: float) -> void:
	advance_effect_time(delta)
	_update_status_display()
	_refresh_elapsed += delta
	if _refresh_elapsed >= 0.25:
		_refresh_elapsed = 0.0
		_refresh_active_targets()


func configure_dependencies(
	production: MonsterProductionManager,
	economy: MonsterEconomy,
	fog: FogOfWarManager
) -> void:
	monster_production = production
	monster_economy = economy
	fog_manager = fog


func activate_round_events(
	cards: Array[AuctionEventCardData],
	outcome: EventAuctionManager.Outcome
) -> void:
	for card in cards:
		if card == null:
			continue
		if card.alignment == AuctionEventCardData.Alignment.HUMAN:
			activate_card(card, FactionComponent.Faction.HUMAN)
		elif card.alignment == AuctionEventCardData.Alignment.MONSTER:
			activate_card(card, FactionComponent.Faction.MONSTER)
		elif (
			outcome == EventAuctionManager.Outcome.HUMAN
			or outcome == EventAuctionManager.Outcome.MONSTER
		):
			var winner := (
				FactionComponent.Faction.HUMAN
				if outcome == EventAuctionManager.Outcome.HUMAN
				else FactionComponent.Faction.MONSTER
			)
			activate_card(card, winner)


func activate_card(
	card: AuctionEventCardData,
	faction: FactionComponent.Faction
) -> bool:
	if card == null or card.effect_kind == AuctionEventCardData.EffectKind.NONE:
		return false
	if _active_effects.has(card.event_id):
		expire_effect(card.event_id)
	_apply_effect(card, faction)
	if card.duration > 0.0:
		_active_effects[card.event_id] = {
			"card": card,
			"faction": faction,
			"remaining": card.duration,
		}
	effect_started.emit(card.event_id, faction, card.duration)
	_update_status_display()
	return true


func advance_effect_time(seconds: float) -> void:
	if seconds <= 0.0 or _active_effects.is_empty():
		return
	var expired: Array[StringName] = []
	for event_id_value in _active_effects.keys():
		var event_id := event_id_value as StringName
		var state := _active_effects[event_id] as Dictionary
		state.remaining = maxf(float(state.remaining) - seconds, 0.0)
		if is_zero_approx(float(state.remaining)):
			expired.append(event_id)
	for event_id in expired:
		expire_effect(event_id)


func expire_effect(event_id: StringName) -> bool:
	if not _active_effects.has(event_id):
		return false
	var state := _active_effects[event_id] as Dictionary
	_active_effects.erase(event_id)
	_remove_effect(
		state.card as AuctionEventCardData,
		int(state.faction) as FactionComponent.Faction
	)
	effect_expired.emit(event_id)
	_update_status_display()
	return true


func is_effect_active(event_id: StringName) -> bool:
	return _active_effects.has(event_id)


func get_effect_remaining(event_id: StringName) -> float:
	if not _active_effects.has(event_id):
		return 0.0
	return float((_active_effects[event_id] as Dictionary).remaining)


func get_active_effect_count() -> int:
	return _active_effects.size()


func _bind_dependencies() -> void:
	monster_production = get_tree().get_first_node_in_group(
		&"monster_production_manager"
	) as MonsterProductionManager
	monster_economy = get_tree().get_first_node_in_group(
		&"monster_economy"
	) as MonsterEconomy
	fog_manager = get_tree().get_first_node_in_group(
		&"human_fog_manager"
	) as FogOfWarManager


func _apply_effect(
	card: AuctionEventCardData,
	faction: FactionComponent.Faction
) -> void:
	match card.effect_kind:
		AuctionEventCardData.EffectKind.TOWER_COMBAT:
			_apply_tower_modifier(card)
		AuctionEventCardData.EffectKind.HUMAN_COMBAT:
			_apply_human_combat(card)
		AuctionEventCardData.EffectKind.MONSTER_COMBAT:
			_apply_monster_combat(card)
		AuctionEventCardData.EffectKind.MONSTER_PRODUCTION_COST:
			if monster_production != null:
				monster_production.set_event_cost_multiplier(
					card.event_id, card.primary_value
				)
		AuctionEventCardData.EffectKind.MONSTER_TYPE_COST:
			if monster_production != null:
				monster_production.set_event_type_cost_multiplier(
					card.event_id, card.target_id, card.primary_value
				)
		AuctionEventCardData.EffectKind.HUMAN_VISION:
			_apply_human_vision(card)
		AuctionEventCardData.EffectKind.MONSTER_INCOME:
			if monster_economy != null:
				monster_economy.set_event_income_multiplier(
					card.event_id, card.primary_value
				)
		AuctionEventCardData.EffectKind.HUMAN_REPAIR:
			_repair_human_buildings(card.primary_value)
		AuctionEventCardData.EffectKind.ECLIPSE:
			_apply_eclipse(card, faction)
		AuctionEventCardData.EffectKind.MAGIC_STORM:
			_apply_magic_storm(card, faction)


func _remove_effect(
	card: AuctionEventCardData,
	faction: FactionComponent.Faction
) -> void:
	match card.effect_kind:
		AuctionEventCardData.EffectKind.TOWER_COMBAT:
			for tower in _get_towers():
				tower.remove_event_combat_modifier(card.event_id)
		AuctionEventCardData.EffectKind.HUMAN_COMBAT:
			for unit in _get_units_for_faction(FactionComponent.Faction.HUMAN):
				if unit.has_method("remove_event_combat_modifier"):
					unit.call("remove_event_combat_modifier", card.event_id)
		AuctionEventCardData.EffectKind.MONSTER_COMBAT:
			for unit in _get_units_for_faction(FactionComponent.Faction.MONSTER):
				if unit is MonsterUnit:
					(unit as MonsterUnit).remove_aura_buff(
						_get_monster_buff_source(card.event_id)
					)
		AuctionEventCardData.EffectKind.MONSTER_PRODUCTION_COST:
			if monster_production != null:
				monster_production.remove_event_cost_multiplier(card.event_id)
		AuctionEventCardData.EffectKind.MONSTER_TYPE_COST:
			if monster_production != null:
				monster_production.remove_event_type_cost_multiplier(card.event_id)
		AuctionEventCardData.EffectKind.HUMAN_VISION:
			for source in _get_human_vision_sources():
				source.remove_event_radius_multiplier(card.event_id)
			if fog_manager != null:
				fog_manager.refresh_visibility()
		AuctionEventCardData.EffectKind.MONSTER_INCOME:
			if monster_economy != null:
				monster_economy.remove_event_income_multiplier(card.event_id)
		AuctionEventCardData.EffectKind.ECLIPSE:
			_remove_eclipse(card, faction)


func _refresh_active_targets() -> void:
	for state_value in _active_effects.values():
		var state := state_value as Dictionary
		_apply_persistent_targets(
			state.card as AuctionEventCardData,
			int(state.faction) as FactionComponent.Faction
		)


func _apply_persistent_targets(
	card: AuctionEventCardData,
	faction: FactionComponent.Faction
) -> void:
	match card.effect_kind:
		AuctionEventCardData.EffectKind.TOWER_COMBAT:
			_apply_tower_modifier(card)
		AuctionEventCardData.EffectKind.HUMAN_COMBAT:
			_apply_human_combat(card)
		AuctionEventCardData.EffectKind.MONSTER_COMBAT:
			_apply_monster_combat(card)
		AuctionEventCardData.EffectKind.HUMAN_VISION:
			_apply_human_vision(card)
		AuctionEventCardData.EffectKind.ECLIPSE:
			if faction == FactionComponent.Faction.MONSTER:
				_apply_tower_modifier(card)


func _apply_tower_modifier(card: AuctionEventCardData) -> void:
	for tower in _get_towers():
		var interval_multiplier := 1.0
		var range_multiplier := 1.0
		if card.effect_kind == AuctionEventCardData.EffectKind.ECLIPSE:
			range_multiplier = card.primary_value
		else:
			interval_multiplier = card.primary_value
		tower.set_event_combat_modifier(
			card.event_id, 1.0, interval_multiplier, range_multiplier
		)


func _apply_human_combat(card: AuctionEventCardData) -> void:
	for unit in _get_units_for_faction(FactionComponent.Faction.HUMAN):
		if unit.has_method("set_event_combat_modifier"):
			unit.call(
				"set_event_combat_modifier",
				card.event_id,
				card.primary_value,
				card.secondary_value
			)


func _apply_monster_combat(card: AuctionEventCardData) -> void:
	for unit in _get_units_for_faction(FactionComponent.Faction.MONSTER):
		if unit is MonsterUnit:
			(unit as MonsterUnit).set_aura_buff(
				_get_monster_buff_source(card.event_id),
				card.primary_value,
				card.secondary_value
			)


func _apply_human_vision(card: AuctionEventCardData) -> void:
	for source in _get_human_vision_sources():
		source.set_event_radius_multiplier(card.event_id, card.primary_value)
	if fog_manager != null:
		fog_manager.refresh_visibility()


func _apply_eclipse(
	card: AuctionEventCardData,
	faction: FactionComponent.Faction
) -> void:
	if faction == FactionComponent.Faction.HUMAN:
		if fog_manager != null:
			_saved_fog_states[card.event_id] = fog_manager.is_human_fog_enabled()
			fog_manager.set_human_fog_enabled(false)
	else:
		_apply_tower_modifier(card)


func _remove_eclipse(
	card: AuctionEventCardData,
	faction: FactionComponent.Faction
) -> void:
	if faction == FactionComponent.Faction.HUMAN:
		if fog_manager != null:
			fog_manager.set_human_fog_enabled(
				bool(_saved_fog_states.get(card.event_id, true))
			)
		_saved_fog_states.erase(card.event_id)
	else:
		for tower in _get_towers():
			tower.remove_event_combat_modifier(card.event_id)


func _repair_human_buildings(ratio: float) -> void:
	for target in get_tree().get_nodes_in_group(&"combat_targets"):
		var faction := FactionComponent.find_on(target)
		var health := target.get_node_or_null("HealthComponent") as HealthComponent
		if (
			faction != null
			and faction.faction == FactionComponent.Faction.HUMAN
			and health != null
		):
			health.heal(health.max_health * maxf(ratio, 0.0))


func _apply_magic_storm(
	card: AuctionEventCardData,
	faction: FactionComponent.Faction
) -> void:
	if faction == FactionComponent.Faction.HUMAN:
		var upgrades_remaining := maxi(roundi(card.primary_value), 0)
		for tower in _get_towers():
			if upgrades_remaining <= 0:
				break
			if tower.apply_upgrade():
				upgrades_remaining -= 1
	elif monster_economy != null:
		monster_economy.add_dark_energy(
			maxi(roundi(card.secondary_value), 0), &"magic_storm"
		)


func _get_towers() -> Array[DefenseTower]:
	var result: Array[DefenseTower] = []
	for node in get_tree().get_nodes_in_group(&"placed_towers"):
		if node is DefenseTower:
			result.append(node as DefenseTower)
	return result


func _get_units_for_faction(
	faction_value: FactionComponent.Faction
) -> Array[Node2D]:
	var result: Array[Node2D] = []
	for node in get_tree().get_nodes_in_group(&"combat_units"):
		var unit := node as Node2D
		var faction := FactionComponent.find_on(unit)
		if faction != null and faction.faction == faction_value:
			result.append(unit)
	return result


func _get_human_vision_sources() -> Array[VisionSourceComponent]:
	var result: Array[VisionSourceComponent] = []
	for node in get_tree().get_nodes_in_group(&"human_vision_sources"):
		if node is VisionSourceComponent:
			result.append(node as VisionSourceComponent)
	return result


func _get_monster_buff_source(event_id: StringName) -> int:
	return 1000000000 + absi(event_id.hash() % 100000000)


func _update_status_display() -> void:
	if status_panel == null or status_label == null:
		return
	status_panel.visible = not _active_effects.is_empty()
	if _active_effects.is_empty():
		return
	var lines := PackedStringArray(["当前事件效果"])
	for state_value in _active_effects.values():
		var state := state_value as Dictionary
		var card := state.card as AuctionEventCardData
		lines.append("%s · %d 秒" % [
			card.title,
			ceili(float(state.remaining)),
		])
	status_label.text = "\n".join(lines)
