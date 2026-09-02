extends Control

signal return_to_main_requested

@onready var return_button: Button = %ReturnButton
@onready var gold_label: Label = %GoldLabel
@onready var dark_energy_label: Label = %DarkEnergyLabel
@onready var dark_energy_rate_label: Label = %DarkEnergyRateLabel
@onready var economy_status_label: Label = %EconomyStatusLabel
@onready var view_mode_button: Button = %ViewModeButton
@onready var spend_test_button: Button = %SpendTestButton
@onready var build_tower_button: Button = %BuildTowerButton
@onready var arrow_tower_button: Button = %ArrowTowerButton
@onready var flame_tower_button: Button = %FlameTowerButton
@onready var frost_tower_button: Button = %FrostTowerButton
@onready var arcane_tower_button: Button = %ArcaneTowerButton
@onready var scout_tower_button: Button = %ScoutTowerButton
@onready var selected_tower_label: Label = %SelectedTowerLabel
@onready var upgrade_tower_button: Button = %UpgradeTowerButton
@onready var swordsman_squad_button: Button = %SwordsmanSquadButton
@onready var archer_squad_button: Button = %ArcherSquadButton
@onready var knight_squad_button: Button = %KnightSquadButton
@onready var mage_squad_button: Button = %MageSquadButton
@onready var monster_production_panel: ColorRect = %MonsterProductionPanel
@onready var selected_nest_label: Label = %SelectedNestLabel
@onready var monster_type_zero_button: Button = %MonsterTypeZeroButton
@onready var monster_type_one_button: Button = %MonsterTypeOneButton
@onready var monster_type_two_button: Button = %MonsterTypeTwoButton
@onready var monster_type_three_button: Button = %MonsterTypeThreeButton
@onready var monster_type_four_button: Button = %MonsterTypeFourButton
@onready var monster_type_five_button: Button = %MonsterTypeFiveButton
@onready var monster_production_status_label: Label = %MonsterProductionStatusLabel
@onready var nest_stage_label: Label = %NestStageLabel

var human_economy: Node
var monster_economy: Node
var building_placement_manager: Node
var human_squad_manager: Node
var monster_production_manager: MonsterProductionManager
var nest_strengthening_manager: NestStrengtheningManager
var fog_of_war_manager: FogOfWarManager


func _ready() -> void:
	return_button.pressed.connect(_on_return_button_pressed)
	view_mode_button.pressed.connect(_on_view_mode_button_pressed)
	spend_test_button.pressed.connect(_on_spend_test_button_pressed)
	build_tower_button.pressed.connect(_on_build_tower_button_pressed)
	arrow_tower_button.pressed.connect(_on_tower_button_pressed.bind(0))
	flame_tower_button.pressed.connect(_on_tower_button_pressed.bind(1))
	frost_tower_button.pressed.connect(_on_tower_button_pressed.bind(2))
	arcane_tower_button.pressed.connect(_on_tower_button_pressed.bind(3))
	scout_tower_button.pressed.connect(_on_tower_button_pressed.bind(4))
	upgrade_tower_button.pressed.connect(_on_upgrade_tower_button_pressed)
	swordsman_squad_button.pressed.connect(_on_squad_button_pressed.bind(0))
	archer_squad_button.pressed.connect(_on_squad_button_pressed.bind(1))
	knight_squad_button.pressed.connect(_on_squad_button_pressed.bind(2))
	mage_squad_button.pressed.connect(_on_squad_button_pressed.bind(3))
	for monster_index in _get_monster_production_buttons().size():
		_get_monster_production_buttons()[monster_index].pressed.connect(
			_on_monster_production_button_pressed.bind(monster_index)
		)
	call_deferred("_bind_human_economy")
	call_deferred("_bind_monster_economy")
	call_deferred("_bind_building_placement_manager")
	call_deferred("_bind_human_squad_manager")
	call_deferred("_bind_monster_production_manager")
	call_deferred("_bind_nest_strengthening_manager")
	call_deferred("_bind_fog_of_war_manager")


func _on_return_button_pressed() -> void:
	return_to_main_requested.emit()


func _on_view_mode_button_pressed() -> void:
	if fog_of_war_manager == null:
		return
	var next_faction := FogOfWarManager.ViewerFaction.MONSTER
	if fog_of_war_manager.is_monster_view_active():
		next_faction = FogOfWarManager.ViewerFaction.HUMAN
	fog_of_war_manager.set_viewer_faction(next_faction)


func _bind_fog_of_war_manager() -> void:
	fog_of_war_manager = get_tree().get_first_node_in_group(
		&"human_fog_manager"
	) as FogOfWarManager
	if fog_of_war_manager == null:
		view_mode_button.text = "VIEW UNAVAILABLE"
		view_mode_button.disabled = true
		return
	fog_of_war_manager.viewer_faction_changed.connect(
		_on_viewer_faction_changed
	)
	_on_viewer_faction_changed(fog_of_war_manager.get_viewer_faction())


func _on_viewer_faction_changed(
	viewer_faction: FogOfWarManager.ViewerFaction
) -> void:
	view_mode_button.text = (
		"VIEW: MONSTER"
		if viewer_faction == FogOfWarManager.ViewerFaction.MONSTER
		else "VIEW: HUMAN"
	)
	view_mode_button.tooltip_text = (
		"Monster overview: full map visibility"
		if viewer_faction == FogOfWarManager.ViewerFaction.MONSTER
		else "Human overview: local vision and fog of war"
	)


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


func _bind_monster_economy() -> void:
	monster_economy = get_tree().get_first_node_in_group(&"monster_economy")
	if monster_economy == null:
		dark_energy_label.text = "DARK: --"
		dark_energy_rate_label.text = "MonsterEconomy unavailable"
		return
	monster_economy.dark_energy_changed.connect(_on_dark_energy_changed)
	monster_economy.income_rate_changed.connect(
		_on_monster_income_rate_changed
	)
	_on_dark_energy_changed(
		monster_economy.call("get_dark_energy"), 0, &"hud_sync"
	)
	_on_monster_income_rate_changed(
		monster_economy.call("get_active_nest_count"),
		monster_economy.call("get_income_per_interval")
	)


func _on_dark_energy_changed(
	current_energy: int, _change: int, _reason: StringName
) -> void:
	dark_energy_label.text = "DARK: %d" % current_energy
	_refresh_monster_production_buttons()


func _on_monster_income_rate_changed(
	active_nests: int, energy_per_interval: int
) -> void:
	var interval := float(monster_economy.get("income_interval"))
	dark_energy_rate_label.text = "+%d every %.1fs · %d nests" % [
		energy_per_interval, interval, active_nests
	]


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


func _on_monster_production_button_pressed(catalog_index: int) -> void:
	if monster_production_manager != null:
		monster_production_manager.produce(catalog_index)


func _bind_monster_production_manager() -> void:
	monster_production_manager = get_tree().get_first_node_in_group(
		&"monster_production_manager"
	) as MonsterProductionManager
	if monster_production_manager == null:
		monster_production_panel.visible = false
		return
	monster_production_manager.nest_selected.connect(
		_on_monster_nest_selected
	)
	monster_production_manager.selection_cleared.connect(
		_on_monster_nest_selection_cleared
	)
	monster_production_manager.monster_produced.connect(
		_on_monster_produced
	)
	monster_production_manager.production_failed.connect(
		_on_monster_production_failed
	)
	monster_production_manager.production_costs_changed.connect(
		_on_monster_production_costs_changed
	)
	_refresh_monster_production_buttons()


func _bind_nest_strengthening_manager() -> void:
	nest_strengthening_manager = get_tree().get_first_node_in_group(
		&"nest_strengthening_manager"
	) as NestStrengtheningManager
	if nest_strengthening_manager == null:
		nest_stage_label.text = ""
		return
	nest_strengthening_manager.stage_changed.connect(
		_on_nest_strengthening_stage_changed
	)
	var profile := nest_strengthening_manager.get_current_profile()
	if profile != null:
		_on_nest_strengthening_stage_changed(
			profile, profile.active_nest_count
		)


func _on_monster_nest_selected(nest: Node2D) -> void:
	monster_production_panel.visible = true
	selected_nest_label.text = str(nest.name).replace(
		"MonsterNest_", "NEST · "
	).to_upper()
	monster_production_status_label.text = "Choose a monster to produce"
	_refresh_monster_production_buttons()


func _on_monster_nest_selection_cleared() -> void:
	monster_production_panel.visible = false


func _on_monster_produced(
	_monster: Node2D,
	_nest: Node2D,
	data: MonsterProductionData,
	cost: int
) -> void:
	monster_production_status_label.text = "%s produced · %d dark" % [
		data.display_name, cost
	]
	_refresh_monster_production_buttons()


func _on_monster_production_failed(reason: StringName) -> void:
	match reason:
		&"not_enough_dark_energy":
			monster_production_status_label.text = "Not enough dark energy"
		&"no_safe_spawn_position":
			monster_production_status_label.text = "Nest exit is blocked"
		&"no_nest_selected":
			monster_production_status_label.text = "Select an active nest"
		_:
			monster_production_status_label.text = "Unable to produce monster"


func _on_monster_production_costs_changed(_multiplier: float) -> void:
	_refresh_monster_production_buttons()


func _on_nest_strengthening_stage_changed(
	profile: NestStrengtheningData, _active_nests: int
) -> void:
	nest_stage_label.text = profile.display_name.to_upper()
	_refresh_monster_production_buttons()


func _refresh_monster_production_buttons() -> void:
	var buttons := _get_monster_production_buttons()
	if monster_production_manager == null:
		for button in buttons:
			button.disabled = true
		return
	var catalog := monster_production_manager.get_production_catalog()
	var has_nest := monster_production_manager.get_selected_nest() != null
	for index in buttons.size():
		var button: Button = buttons[index]
		if index >= catalog.size():
			button.visible = false
			continue
		var data := catalog[index] as MonsterProductionData
		button.visible = true
		var effective_cost := monster_production_manager.get_effective_cost(
			index
		)
		button.text = "%s\n%d DARK" % [
			data.display_name.to_upper(), effective_cost
		]
		button.tooltip_text = data.role_description
		button.disabled = (
			not has_nest
			or monster_economy == null
			or not monster_economy.can_afford(effective_cost)
		)


func _get_monster_production_buttons() -> Array[Button]:
	return [
		monster_type_zero_button,
		monster_type_one_button,
		monster_type_two_button,
		monster_type_three_button,
		monster_type_four_button,
		monster_type_five_button,
	]


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
		scout_tower_button,
	]


func _get_squad_buttons() -> Array[Button]:
	return [
		swordsman_squad_button,
		archer_squad_button,
		knight_squad_button,
		mage_squad_button,
	]
