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
@onready var selected_tower_label: Label = %SelectedTowerLabel
@onready var upgrade_tower_button: Button = %UpgradeTowerButton
@onready var swordsman_squad_button: Button = %SwordsmanSquadButton
@onready var archer_squad_button: Button = %ArcherSquadButton
@onready var knight_squad_button: Button = %KnightSquadButton
@onready var mage_squad_button: Button = %MageSquadButton

var human_economy: Node
var building_placement_manager: Node
var human_squad_manager: Node


func _ready() -> void:
	return_button.pressed.connect(_on_return_button_pressed)
	spend_test_button.pressed.connect(_on_spend_test_button_pressed)
	build_tower_button.pressed.connect(_on_build_tower_button_pressed)
	arrow_tower_button.pressed.connect(_on_tower_button_pressed.bind(0))
	flame_tower_button.pressed.connect(_on_tower_button_pressed.bind(1))
	frost_tower_button.pressed.connect(_on_tower_button_pressed.bind(2))
	arcane_tower_button.pressed.connect(_on_tower_button_pressed.bind(3))
	upgrade_tower_button.pressed.connect(_on_upgrade_tower_button_pressed)
	swordsman_squad_button.pressed.connect(_on_squad_button_pressed.bind(0))
	archer_squad_button.pressed.connect(_on_squad_button_pressed.bind(1))
	knight_squad_button.pressed.connect(_on_squad_button_pressed.bind(2))
	mage_squad_button.pressed.connect(_on_squad_button_pressed.bind(3))
	call_deferred("_bind_human_economy")
	call_deferred("_bind_building_placement_manager")
	call_deferred("_bind_human_squad_manager")


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


func _on_upgrade_tower_button_pressed() -> void:
	if building_placement_manager != null:
		building_placement_manager.call("upgrade_selected_tower")


func _on_squad_button_pressed(squad_index: int) -> void:
	if human_squad_manager != null:
		human_squad_manager.call("recruit_squad", squad_index)


func _bind_human_squad_manager() -> void:
	human_squad_manager = get_tree().get_first_node_in_group(
		&"human_squad_manager"
	)
	if human_squad_manager == null:
		for squad_button in _get_squad_buttons():
			squad_button.disabled = true
		return
	human_squad_manager.squad_recruited.connect(_on_squad_recruited)
	human_squad_manager.recruitment_failed.connect(_on_recruitment_failed)


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
	building_placement_manager.tower_selection_changed.connect(
		_on_tower_selection_changed
	)
	building_placement_manager.tower_upgraded.connect(_on_tower_upgraded)
	building_placement_manager.tower_upgrade_failed.connect(
		_on_tower_upgrade_failed
	)


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
		&"tower_upgrade":
			economy_status_label.text = "%d tower upgrade" % change
		&"squad_recruitment":
			economy_status_label.text = "%d squad recruitment" % change
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


func _on_tower_selection_changed(tower: Node2D) -> void:
	if tower == null:
		selected_tower_label.text = "SELECT A TOWER"
		upgrade_tower_button.text = "UPGRADE"
		upgrade_tower_button.disabled = true
		return
	var data = tower.call("get_tower_data")
	selected_tower_label.text = str(data.get("display_name")).to_upper()
	if tower.call("is_upgraded"):
		upgrade_tower_button.text = "LEVEL 2 — MAX"
		upgrade_tower_button.disabled = true
	else:
		upgrade_tower_button.text = "UPGRADE — %d GOLD" % int(
			tower.call("get_upgrade_cost")
		)
		upgrade_tower_button.disabled = false


func _on_tower_upgraded(tower: Node2D, cost: int) -> void:
	_on_tower_selection_changed(tower)
	economy_status_label.text = "Tower upgraded for %d gold" % cost


func _on_tower_upgrade_failed(reason: StringName) -> void:
	match reason:
		&"not_enough_gold":
			economy_status_label.text = "Not enough gold to upgrade"
		&"already_upgraded":
			economy_status_label.text = "Tower is already level 2"
		_:
			economy_status_label.text = "Select a placed tower first"


func _on_squad_recruited(
	_squad: Node2D, data: HumanSquadData, cost: int
) -> void:
	economy_status_label.text = "%s recruited for %d gold" % [
		data.display_name, cost
	]


func _on_recruitment_failed(reason: StringName) -> void:
	if reason == &"not_enough_gold":
		economy_status_label.text = "Not enough gold to recruit squad"
	else:
		economy_status_label.text = "Unable to recruit squad"


func _get_tower_buttons() -> Array[Button]:
	return [
		arrow_tower_button,
		flame_tower_button,
		frost_tower_button,
		arcane_tower_button,
	]


func _get_squad_buttons() -> Array[Button]:
	return [
		swordsman_squad_button,
		archer_squad_button,
		knight_squad_button,
		mage_squad_button,
	]
