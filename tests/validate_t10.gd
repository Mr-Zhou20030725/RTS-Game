extends SceneTree

const ECONOMY_SCENE := preload("res://scenes/economy/human_economy.tscn")
const PLACEMENT_SCENE := preload(
	"res://scenes/building/building_placement_manager.tscn"
)
const HUD_SCENE := preload("res://ui/battle_hud/battle_hud.tscn")
const BASE_SCENE := preload(
	"res://buildings/placeholders/human_base_placeholder.tscn"
)


func _init() -> void:
	_run_validation()


func _run_validation() -> void:
	var economy = ECONOMY_SCENE.instantiate()
	economy.starting_gold = 100
	economy.passive_income_amount = 0
	var placement = PLACEMENT_SCENE.instantiate()
	var base := BASE_SCENE.instantiate()
	base.position = Vector2(640, 384)
	root.add_child(economy)
	root.add_child(placement)
	root.add_child(base)
	await process_frame

	var hud := HUD_SCENE.instantiate()
	root.add_child(hud)
	await process_frame
	await process_frame
	(hud.get_node("TopBar/BuildTowerButton") as Button).pressed.emit()
	if not placement.is_build_mode_active():
		_fail("Tower HUD button did not enter build preview mode.")
		return
	var gold_before_cancel: int = economy.get_gold()
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	right_click.position = Vector2(300, 300)
	Input.parse_input_event(right_click)
	await process_frame
	if placement.is_build_mode_active():
		_fail("Right click did not cancel build mode.")
		return
	if economy.get_gold() != gold_before_cancel:
		_fail("Cancelling build mode deducted gold.")
		return

	var valid_position := Vector2(288, 288)
	if not placement.begin_placement(
		placement.default_building_scene, 50, valid_position
	):
		_fail("Could not enter build mode at an affordable valid position.")
		return
	if not placement.is_preview_position_valid():
		_fail("Open terrain was not shown as a valid green preview.")
		return
	if placement.get_preview().modulate != placement.valid_preview_color:
		_fail("Valid preview did not use the configured green color.")
		return
	if not placement.confirm_placement():
		_fail("Valid preview could not be confirmed.")
		return
	if economy.get_gold() != 50:
		_fail("Confirmed building did not deduct exactly 50 gold.")
		return
	if placement.get_placed_buildings().size() != 1:
		_fail("Confirmed tower was not retained as a placed building.")
		return

	var gold_before_overlap: int = economy.get_gold()
	placement.begin_placement(
		placement.default_building_scene, 50, valid_position
	)
	if placement.is_preview_position_valid():
		_fail("Preview overlapping an existing tower was marked valid.")
		return
	if placement.get_preview().modulate != placement.invalid_preview_color:
		_fail("Overlapping preview did not use the configured red color.")
		return
	if placement.confirm_placement():
		_fail("A tower was built on top of an existing tower.")
		return
	placement.cancel_placement()
	if economy.get_gold() != gold_before_overlap:
		_fail("Invalid overlap attempt changed the gold balance.")
		return

	placement.begin_placement(
		placement.default_building_scene, 50, Vector2(16, 16)
	)
	if placement.is_preview_position_valid() or placement.confirm_placement():
		_fail("A tower was accepted outside the playable build bounds.")
		return
	placement.cancel_placement()
	if economy.get_gold() != gold_before_overlap:
		_fail("Out-of-bounds placement attempt deducted gold.")
		return

	placement.begin_placement(
		placement.default_building_scene, 50, base.global_position
	)
	if placement.is_preview_position_valid() or placement.confirm_placement():
		_fail("A tower was accepted on top of the Human base.")
		return
	placement.cancel_placement()
	if economy.get_gold() != gold_before_overlap:
		_fail("Base-overlap placement attempt deducted gold.")
		return

	if not economy.try_spend(50, &"test_setup"):
		_fail("Could not prepare the insufficient-gold test.")
		return
	if placement.begin_placement(
		placement.default_building_scene, 50, Vector2(400, 500)
	):
		_fail("Build mode opened despite insufficient gold.")
		return
	if placement.is_build_mode_active():
		_fail("Insufficient gold left an active construction preview.")
		return
	if economy.get_gold() != 0:
		_fail("Insufficient build attempt made the balance negative.")
		return
	if placement.get_placed_buildings().size() != 1:
		_fail("Invalid attempts changed the number of placed towers.")
		return

	print(
		"T10 validation passed: HUD entry, green/red preview, bounds and "
		+ "overlap checks, atomic spending, insufficient funds, and cancel."
	)
	quit()


func _fail(message: String) -> void:
	push_error("T10 validation failed: %s" % message)
	quit(1)
