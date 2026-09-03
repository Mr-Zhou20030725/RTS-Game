extends SceneTree

const TIME_SCENE := preload("res://scenes/time/game_time_manager.tscn")
const AUCTION_SCENE := preload(
	"res://scenes/events/event_auction_manager.tscn"
)
const HUMAN_ECONOMY_SCENE := preload(
	"res://scenes/economy/human_economy.tscn"
)
const MONSTER_ECONOMY_SCENE := preload(
	"res://scenes/economy/monster_economy.tscn"
)
const BATTLE_SCENE := preload("res://scenes/battle/battle.tscn")


func _init() -> void:
	_run_validation()


func _run_validation() -> void:
	var host := Node.new()
	host.name = "T28TestHost"
	root.add_child(host)
	var time_manager := TIME_SCENE.instantiate() as GameTimeManager
	var human := HUMAN_ECONOMY_SCENE.instantiate() as HumanEconomy
	var monster := MONSTER_ECONOMY_SCENE.instantiate() as MonsterEconomy
	var auction := AUCTION_SCENE.instantiate() as EventAuctionManager
	time_manager.set_process(false)
	human.set_process(false)
	monster.set_process(false)
	host.add_child(time_manager)
	host.add_child(human)
	host.add_child(monster)
	host.add_child(auction)
	await process_frame
	await process_frame
	time_manager.set_process(false)
	human.set_process(false)
	monster.set_process(false)
	auction.configure_dependencies(
		time_manager,
		human,
		monster,
		GameManager.PlayerFaction.HUMAN
	)

	var card_count := 0
	for node in auction.find_children("*", "Label", true, false):
		if node.is_in_group(&"event_auction_card"):
			card_count += 1
	if card_count != 5 or auction.config.get_neutral_card() == null:
		_fail("Auction does not display two Human, two Monster, and one neutral card.")
		return

	time_manager.jump_to_time(300.0)
	if (
		not paused
		or not auction.is_auction_active()
		or not time_manager.is_time_paused()
		or not auction.overlay.visible
	):
		_fail("Five-minute auction did not truly pause and cover the battlefield.")
		return
	var frozen_time := time_manager.elapsed_seconds
	time_manager._process(30.0)
	if not is_equal_approx(time_manager.elapsed_seconds, frozen_time):
		_fail("Game time advanced while the auction was active.")
		return

	var starting_gold := human.get_gold()
	var starting_energy := monster.get_dark_energy()
	if auction.submit_player_bid(starting_gold + 1):
		_fail("A player bid above available resources was accepted.")
		return
	if (
		human.get_gold() != starting_gold
		or monster.get_dark_energy() != starting_energy
	):
		_fail("A rejected bid changed faction resources.")
		return
	if not auction.submit_player_bid(20):
		_fail("A valid Human bid was rejected.")
		return
	if (
		auction.get_last_outcome() != EventAuctionManager.Outcome.HUMAN
		or auction.get_last_human_bid() != 20
		or auction.get_last_monster_bid() != 10
		or human.get_gold() != starting_gold - 20 + 10
		or monster.get_dark_energy() != starting_energy
		or not auction.has_awarded_effect(
			FactionComponent.Faction.HUMAN,
			&"neutral_ancient_relic"
		)
	):
		_fail("Winning bid, deduction, or neutral event reward was incorrect.")
		return
	auction.finish_auction()
	if paused or auction.is_auction_active() or time_manager.is_time_paused():
		_fail("Battle did not resume after the first auction.")
		return

	var gold_before_tie := human.get_gold()
	var energy_before_tie := monster.get_dark_energy()
	time_manager.jump_to_time(900.0)
	if not auction.is_auction_active() or not paused:
		_fail("Fifteen-minute auction did not start.")
		return
	if not auction.submit_player_bid(18):
		_fail("A valid tie bid was rejected.")
		return
	if (
		auction.get_last_outcome() != EventAuctionManager.Outcome.TIE
		or human.get_gold() != gold_before_tie
		or monster.get_dark_energy() != energy_before_tie
		or auction.get_awarded_effect_count() != 1
	):
		_fail("Tie rule deducted resources or awarded the neutral event.")
		return
	auction.finish_auction()
	if paused:
		_fail("Battle stayed paused after resolving the tie.")
		return

	var monster_auction := AUCTION_SCENE.instantiate() as EventAuctionManager
	host.add_child(monster_auction)
	await process_frame
	monster_auction.configure_dependencies(
		time_manager,
		human,
		monster,
		GameManager.PlayerFaction.MONSTER
	)
	monster.add_dark_energy(100, &"t28_test_budget")
	var energy_before_win := monster.get_dark_energy()
	if (
		not monster_auction.begin_auction(1)
		or not monster_auction.submit_player_bid(30)
		or monster_auction.get_last_outcome()
		!= EventAuctionManager.Outcome.MONSTER
		or monster.get_dark_energy() != energy_before_win - 30 + 10
		or not monster_auction.has_awarded_effect(
			FactionComponent.Faction.MONSTER,
			&"neutral_ancient_relic"
		)
	):
		_fail("Monster player bidding did not use dark energy or award its effect.")
		return
	monster_auction.finish_auction()

	var battle := BATTLE_SCENE.instantiate()
	if battle.get_node_or_null("EventAuctionManager") == null:
		battle.free()
		_fail("Battle scene is missing EventAuctionManager.")
		return
	battle.free()
	print(
		"T28 validation passed: 5/15-minute auctions pause the battle, "
		+ "show five cards, enforce faction budgets, resolve hidden bids "
		+ "and ties, award the neutral effect, and resume play."
	)
	quit()


func _fail(message: String) -> void:
	paused = false
	push_error("T28 validation failed: %s" % message)
	quit(1)
