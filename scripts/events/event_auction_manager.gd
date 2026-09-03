class_name EventAuctionManager
extends CanvasLayer

signal auction_started(round_index: int)
signal bid_rejected(requested_bid: int, available_resource: int)
signal auction_resolved(
	outcome: Outcome,
	human_bid: int,
	monster_bid: int,
	event_id: StringName
)
signal event_effect_awarded(
	faction: FactionComponent.Faction,
	event_id: StringName
)
signal auction_finished(round_index: int)

enum Outcome {
	NONE,
	HUMAN,
	MONSTER,
	TIE,
}

@export var config: EventAuctionConfig

var game_time_manager: GameTimeManager
var human_economy: HumanEconomy
var monster_economy: MonsterEconomy
var player_faction := GameManager.PlayerFaction.HUMAN
var _active_round := 0
var _active := false
var _resolved := false
var _opponent_bid := 0
var _last_human_bid := 0
var _last_monster_bid := 0
var _last_outcome := Outcome.NONE
var _resolved_rounds: Dictionary = {}
var _awarded_effects: Array[Dictionary] = []

@onready var overlay: Control = $Overlay
@onready var round_label: Label = %RoundLabel
@onready var resource_label: Label = %ResourceLabel
@onready var bid_input: SpinBox = %BidInput
@onready var submit_button: Button = %SubmitBidButton
@onready var continue_button: Button = %ContinueButton
@onready var result_label: Label = %ResultLabel
@onready var rule_label: Label = %RuleLabel


func _ready() -> void:
	overlay.hide()
	submit_button.pressed.connect(_on_submit_pressed)
	continue_button.pressed.connect(finish_auction)
	call_deferred("_bind_battle_dependencies")
	_refresh_card_display()


func configure_dependencies(
	time_manager: GameTimeManager,
	human: HumanEconomy,
	monster: MonsterEconomy,
	selected_player_faction: int
) -> void:
	if game_time_manager != null and game_time_manager.milestone_reached.is_connected(
		_on_milestone_reached
	):
		game_time_manager.milestone_reached.disconnect(_on_milestone_reached)
	game_time_manager = time_manager
	human_economy = human
	monster_economy = monster
	if selected_player_faction in [
		GameManager.PlayerFaction.HUMAN,
		GameManager.PlayerFaction.MONSTER,
	]:
		player_faction = selected_player_faction
	if game_time_manager != null and not game_time_manager.milestone_reached.is_connected(
		_on_milestone_reached
	):
		game_time_manager.milestone_reached.connect(_on_milestone_reached)


func begin_auction(round_index: int) -> bool:
	if (
		_active
		or round_index not in [1, 2]
		or _resolved_rounds.has(round_index)
		or human_economy == null
		or monster_economy == null
		or game_time_manager == null
	):
		return false
	_active = true
	_resolved = false
	_active_round = round_index
	_last_human_bid = 0
	_last_monster_bid = 0
	_last_outcome = Outcome.NONE
	_opponent_bid = _calculate_opponent_bid()
	_prepare_bid_controls()
	overlay.show()
	game_time_manager.pause_time()
	get_tree().paused = true
	auction_started.emit(_active_round)
	return true


func submit_player_bid(amount: int) -> bool:
	if not _active or _resolved or amount < 0:
		return false
	var available := _get_player_resource()
	if amount > available:
		result_label.text = "出价失败：不能超过当前%s %d。" % [
			_get_player_resource_name(),
			available,
		]
		bid_rejected.emit(amount, available)
		return false
	if player_faction == GameManager.PlayerFaction.MONSTER:
		_last_human_bid = _opponent_bid
		_last_monster_bid = amount
	else:
		_last_human_bid = amount
		_last_monster_bid = _opponent_bid
	_resolve_auction()
	return true


func finish_auction() -> void:
	if not _active or not _resolved:
		return
	var finished_round := _active_round
	overlay.hide()
	_active = false
	_active_round = 0
	get_tree().paused = false
	game_time_manager.resume_time()
	auction_finished.emit(finished_round)


func is_auction_active() -> bool:
	return _active


func is_auction_resolved() -> bool:
	return _resolved


func get_last_outcome() -> Outcome:
	return _last_outcome


func get_last_human_bid() -> int:
	return _last_human_bid


func get_last_monster_bid() -> int:
	return _last_monster_bid


func get_awarded_effect_count() -> int:
	return _awarded_effects.size()


func has_awarded_effect(
	faction: FactionComponent.Faction,
	event_id: StringName
) -> bool:
	for award in _awarded_effects:
		if award.faction == faction and award.event_id == event_id:
			return true
	return false


func _bind_battle_dependencies() -> void:
	var battle := get_parent()
	if battle == null:
		return
	var selected_faction := GameManager.PlayerFaction.HUMAN
	if battle.has_method("get_player_faction"):
		selected_faction = int(battle.call("get_player_faction"))
	configure_dependencies(
		battle.get_node_or_null("GameTimeManager") as GameTimeManager,
		battle.get_node_or_null("HumanEconomy") as HumanEconomy,
		battle.get_node_or_null("MonsterEconomy") as MonsterEconomy,
		selected_faction
	)


func _on_milestone_reached(
	milestone: GameTimeManager.Milestone,
	_elapsed_seconds: float
) -> void:
	if milestone == GameTimeManager.Milestone.MINUTE_5:
		begin_auction(1)
	elif milestone == GameTimeManager.Milestone.MINUTE_15:
		begin_auction(2)


func _calculate_opponent_bid() -> int:
	var available := (
		human_economy.get_gold()
		if player_faction == GameManager.PlayerFaction.MONSTER
		else monster_economy.get_dark_energy()
	)
	if available <= 0:
		return 0
	var desired := roundi(float(available) * config.get_ai_bid_ratio(_active_round))
	return clampi(maxi(desired, config.minimum_ai_bid), 0, available)


func _prepare_bid_controls() -> void:
	var available := _get_player_resource()
	var minute := 5 if _active_round == 1 else 15
	round_label.text = "第 %d 轮事件竞拍 · %d 分钟" % [
		_active_round,
		minute,
	]
	resource_label.text = "你的%s：%d · 对方已秘密出价" % [
		_get_player_resource_name(),
		available,
	]
	bid_input.max_value = available
	bid_input.value = mini(available, 10)
	bid_input.editable = true
	submit_button.disabled = false
	continue_button.hide()
	result_label.text = "输入对中立牌的秘密出价，然后同时揭晓。"
	rule_label.text = (
		"第一价格竞拍：仅赢家支付出价；输家不扣费。\n"
		+ config.tie_rule_text
	)


func _resolve_auction() -> void:
	_resolved = true
	_resolved_rounds[_active_round] = true
	if _last_human_bid > _last_monster_bid:
		_last_outcome = Outcome.HUMAN
		if not human_economy.try_spend(_last_human_bid, &"event_auction"):
			_abort_resolution()
			return
		_award_neutral_effect(FactionComponent.Faction.HUMAN)
	elif _last_monster_bid > _last_human_bid:
		_last_outcome = Outcome.MONSTER
		if not monster_economy.try_spend(
			_last_monster_bid, &"event_auction"
		):
			_abort_resolution()
			return
		_award_neutral_effect(FactionComponent.Faction.MONSTER)
	else:
		_last_outcome = Outcome.TIE
	bid_input.editable = false
	submit_button.disabled = true
	continue_button.show()
	result_label.text = _build_result_text()
	var neutral_card := config.get_neutral_card()
	var event_id := neutral_card.event_id if neutral_card != null else &""
	auction_resolved.emit(
		_last_outcome,
		_last_human_bid,
		_last_monster_bid,
		event_id
	)


func _abort_resolution() -> void:
	_resolved = false
	_resolved_rounds.erase(_active_round)
	_last_outcome = Outcome.NONE
	result_label.text = "资源状态发生变化，请重新出价。"
	_prepare_bid_controls()


func _award_neutral_effect(faction: FactionComponent.Faction) -> void:
	var neutral_card := config.get_neutral_card()
	if neutral_card == null:
		return
	_awarded_effects.append({
		"faction": faction,
		"event_id": neutral_card.event_id,
		"round": _active_round,
	})
	if neutral_card.resource_reward > 0:
		if faction == FactionComponent.Faction.HUMAN:
			human_economy.add_gold(
				neutral_card.resource_reward, &"auction_event_reward"
			)
		else:
			monster_economy.add_dark_energy(
				neutral_card.resource_reward, &"auction_event_reward"
			)
	event_effect_awarded.emit(faction, neutral_card.event_id)


func _build_result_text() -> String:
	var bids := "人类出价 %d 金币 · 怪物出价 %d 暗能量\n" % [
		_last_human_bid,
		_last_monster_bid,
	]
	if _last_outcome == Outcome.TIE:
		return bids + "平价：中立牌无人获得，双方均未扣费。"
	var winner := "人类" if _last_outcome == Outcome.HUMAN else "怪物"
	var neutral_card := config.get_neutral_card()
	var effect_text := (
		neutral_card.effect_summary
		if neutral_card != null
		else "中立事件效果"
	)
	return bids + "%s获胜并获得：%s" % [winner, effect_text]


func _get_player_resource() -> int:
	return (
		monster_economy.get_dark_energy()
		if player_faction == GameManager.PlayerFaction.MONSTER
		else human_economy.get_gold()
	)


func _get_player_resource_name() -> String:
	return (
		"暗能量"
		if player_faction == GameManager.PlayerFaction.MONSTER
		else "金币"
	)


func _refresh_card_display() -> void:
	if config == null:
		return
	var labels: Array[Label] = [
		$Overlay/AuctionPanel/Content/HumanCardOne/CardLabel,
		$Overlay/AuctionPanel/Content/HumanCardTwo/CardLabel,
		$Overlay/AuctionPanel/Content/MonsterCardOne/CardLabel,
		$Overlay/AuctionPanel/Content/MonsterCardTwo/CardLabel,
		$Overlay/AuctionPanel/Content/NeutralCard/CardLabel,
	]
	for index in mini(labels.size(), config.cards.size()):
		var label := labels[index]
		var card := config.cards[index]
		if label == null or card == null:
			continue
		var alignment_text := "中立争夺"
		if card.alignment == AuctionEventCardData.Alignment.HUMAN:
			alignment_text = "人类事件"
		elif card.alignment == AuctionEventCardData.Alignment.MONSTER:
			alignment_text = "怪物事件"
		label.text = "%s\n\n%s\n\n%s" % [
			alignment_text,
			card.title,
			card.description,
		]


func _on_submit_pressed() -> void:
	submit_player_bid(roundi(bid_input.value))
