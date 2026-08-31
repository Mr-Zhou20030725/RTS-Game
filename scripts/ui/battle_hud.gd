extends Control

signal return_to_main_requested

@onready var return_button: Button = %ReturnButton
@onready var gold_label: Label = %GoldLabel
@onready var economy_status_label: Label = %EconomyStatusLabel
@onready var spend_test_button: Button = %SpendTestButton
@onready var build_tower_button: Button = %BuildTowerButton
@onready var arrow_tower_button: Button = %ArrowTowerButton
@onready var flame_tower_button: Button = %FlameTowerButton
@onready var frost_tower_button: Button = %FrostTowerButton
@onready var arcane_tower_button: Button = %ArcaneTowerButton

var human_economy: Node
var building_placement_manager: Node


func _ready() -> void:
	return_button.pressed.connect(_on_return_button_pressed)
	spend_test_button.pressed.connect(_on_spend_test_button_pressed)
	build_tower_button.pressed.connect(_on_build_tower_button_pressed)
	arrow_tower_button.pressed.connect(_on_tower_button_pressed.bind(0))
	flame_tower_button.pressed.connect(_on_tower_button_pressed.bind(1))
	frost_tower_button.pressed.connect(_on_tower_button_pressed.bind(2))
	arcane_tower_button.pressed.connect(_on_tower_button_pressed.bind(3))
	call_deferred("_bind_human_economy")
	call_deferred("_bind_building_placement_manager")


func _on_return_button_pressed() -> void:
	return_to_main_requested.emit()


func _bind_human_economy() -> void:
	human_economy = get_tree().get_first_node_in_group(&"human_economy")
	if human_economy == null:
		gold_label.text = "GOLD: --"
		economy_status_label.text = "HumanEconomy unavailable"
		spend_test_button.disabled = true
		return

	human_economy.gold_changed.connect(_on_gold_changed)
	human_economy.spend_rejected.connect(_on_spend_rejected)
	_on_gold_changed(human_economy.call("get_gold"), 0, &"hud_sync")


func _on_spend_test_button_pressed() -> void:
	if human_economy == null:
		return
	human_economy.call("try_spend", 50, &"t09_test_spend")


func _on_build_tower_button_pressed() -> void:
	if building_placement_manager == null:
		return
	building_placement_manager.call("begin_default_placement")


func _on_tower_button_pressed(tower_index: int) -> void:
	if building_placement_manager == null:
		return
	building_placement_manager.call("begin_tower_placement", tower_index)


func _bind_building_placement_manager() -> void:
	building_placement_manager = get_tree().get_first_node_in_group(
		&"building_placement_manager"
	)
	if building_placement_manager == null:
		build_tower_button.disabled = true
		for tower_button in _get_tower_buttons():
			tower_button.disabled = true
		economy_status_label.text = "Placement manager unavailable"
		return

	building_placement_manager.build_mode_changed.connect(
		_on_build_mode_changed
	)
	building_placement_manager.preview_validity_changed.connect(
		_on_preview_validity_changed
	)
	building_placement_manager.building_placed.connect(_on_building_placed)
	building_placement_manager.placement_failed.connect(_on_placement_failed)


func _on_gold_changed(
	current_gold: int, change: int, reason: StringName
) -> void:
	gold_label.text = "GOLD: %d" % current_gold
	match reason:
		&"passive_income":
			economy_status_label.text = "+%d passive income" % change
		&"monster_kill":
			economy_status_label.text = "+%d monster reward" % change
		&"t09_test_spend":
			economy_status_label.text = "%d test spend" % change
		&"tower_construction":
			economy_status_label.text = "%d tower construction" % change
		&"starting_gold":
			economy_status_label.text = "Economy ready"


func _on_spend_rejected(cost: int, current_gold: int) -> void:
	economy_status_label.text = "Need %d gold (have %d)" % [cost, current_gold]


func _on_build_mode_changed(active: bool) -> void:
	build_tower_button.text = (
		"PLACING — RMB CANCEL"
		if active
		else "BUILD TEST TOWER — 50"
	)
	if not active:
		economy_status_label.text = "Build mode closed"


func _on_preview_validity_changed(is_valid: bool) -> void:
	economy_status_label.text = (
		"Green: left click to build"
		if is_valid
		else "Red: invalid build position"
	)


func _on_building_placed(_building: Node2D, cost: int) -> void:
	economy_status_label.text = "Tower placed for %d gold" % cost


func _on_placement_failed(reason: StringName) -> void:
	match reason:
		&"not_enough_gold":
			economy_status_label.text = "Not enough gold to build"
		&"invalid_position":
			economy_status_label.text = "Red position cannot be built"
		_:
			economy_status_label.text = "Unable to enter build mode"


func _get_tower_buttons() -> Array[Button]:
	return [
		arrow_tower_button,
		flame_tower_button,
		frost_tower_button,
		arcane_tower_button,
	]
