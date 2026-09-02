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
@onready var monster_command_panel: ColorRect = %MonsterCommandPanel
@onready var create_legion_button: Button = %CreateLegionButton
@onready var legion_status_label: Label = %LegionStatusLabel
@onready var monster_ai_button: Button = %MonsterAIButton
@onready var monster_ai_status_label: Label = %MonsterAIStatusLabel
@onready var human_ai_button: Button = %HumanAIButton
@onready var tower_build_bar: ColorRect = %TowerBuildBar
@onready var squad_recruit_bar: ColorRect = %SquadRecruitBar

var human_economy: Node
var monster_economy: Node
var building_placement_manager: Node
var human_squad_manager: Node
var monster_production_manager: MonsterProductionManager
var nest_strengthening_manager: NestStrengtheningManager
var fog_of_war_manager: FogOfWarManager
var monster_legion_manager: MonsterLegionManager
var monster_ai_controller: MonsterAIController
var human_ai_controller: HumanAIController
var _player_faction := GameManager.PlayerFaction.NONE
var _faction_locked := false


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
	create_legion_button.pressed.connect(_on_create_legion_button_pressed)
	monster_ai_button.pressed.connect(_on_monster_ai_button_pressed)
	human_ai_button.pressed.connect(_on_human_ai_button_pressed)
	for slot_index in _get_legion_buttons().size():
		_get_legion_buttons()[slot_index].pressed.connect(
			_on_legion_button_pressed.bind(slot_index + 1)
		)
	call_deferred("_bind_human_economy")
	call_deferred("_bind_monster_economy")
	call_deferred("_bind_building_placement_manager")
	call_deferred("_bind_human_squad_manager")
	call_deferred("_bind_monster_production_manager")
	call_deferred("_bind_nest_strengthening_manager")
	call_deferred("_bind_fog_of_war_manager")
	call_deferred("_bind_monster_legion_manager")
	call_deferred("_bind_monster_ai_controller")
	call_deferred("_bind_human_ai_controller")


func _on_return_button_pressed() -> void:
	return_to_main_requested.emit()


func _on_view_mode_button_pressed() -> void:
	if _faction_locked:
		return
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
		view_mode_button.text = "视角不可用"
		view_mode_button.disabled = true
		return
	fog_of_war_manager.viewer_faction_changed.connect(
		_on_viewer_faction_changed
	)
	_on_viewer_faction_changed(fog_of_war_manager.get_viewer_faction())


func _on_viewer_faction_changed(
	viewer_faction: FogOfWarManager.ViewerFaction
) -> void:
	if _faction_locked:
		_apply_locked_faction_presentation()
		return
	view_mode_button.text = (
		"视角：怪物"
		if viewer_faction == FogOfWarManager.ViewerFaction.MONSTER
		else "视角：人类"
	)
	view_mode_button.tooltip_text = (
		"怪物视角：全地图视野"
		if viewer_faction == FogOfWarManager.ViewerFaction.MONSTER
		else "人类视角：局部视野与战争迷雾"
	)
	monster_command_panel.visible = (
		viewer_faction == FogOfWarManager.ViewerFaction.MONSTER
	)


func configure_player_faction(player_faction: int) -> void:
	if player_faction not in [
		GameManager.PlayerFaction.HUMAN,
		GameManager.PlayerFaction.MONSTER,
	]:
		return
	_player_faction = player_faction
	_faction_locked = true
	_apply_locked_faction_presentation()


func get_player_faction() -> int:
	return _player_faction


func is_faction_locked() -> bool:
	return _faction_locked


func _apply_locked_faction_presentation() -> void:
	var human_selected := _player_faction == GameManager.PlayerFaction.HUMAN
	view_mode_button.disabled = true
	view_mode_button.text = (
		"当前阵营：人类" if human_selected else "当前阵营：怪物"
	)
	view_mode_button.tooltip_text = (
		"已选择人类阵营 · 怪物由 AI 控制"
		if human_selected
		else "已选择怪物阵营 · 人类由 AI 控制"
	)
	tower_build_bar.visible = human_selected
	squad_recruit_bar.visible = human_selected
	monster_command_panel.visible = not human_selected
	if human_selected:
		monster_production_panel.visible = false
	human_ai_button.visible = false
	monster_ai_button.visible = false


func _bind_monster_legion_manager() -> void:
	monster_legion_manager = get_tree().get_first_node_in_group(
		&"monster_legion_manager"
	) as MonsterLegionManager
	if monster_legion_manager == null:
		create_legion_button.disabled = true
		legion_status_label.text = "军团管理器不可用"
		return
	monster_legion_manager.legion_changed.connect(_on_legion_changed)
	monster_legion_manager.active_legion_changed.connect(
		_on_active_legion_changed
	)
	monster_legion_manager.legion_creation_failed.connect(
		_on_legion_creation_failed
	)
	_refresh_legion_buttons()


func _on_create_legion_button_pressed() -> void:
	if monster_legion_manager == null:
		return
	var slot := monster_legion_manager.create_next_legion()
	if slot > 0:
		legion_status_label.text = "军团 %d 已创建 · Ctrl+%d 更新" % [
			slot, slot
		]


func _on_legion_button_pressed(slot: int) -> void:
	if monster_legion_manager == null:
		return
	if monster_legion_manager.select_legion(slot):
		legion_status_label.text = "已选择军团 %d" % slot
	else:
		legion_status_label.text = "军团 %d 为空" % slot


func _on_legion_changed(_slot: int, _units: Array[Node2D]) -> void:
	_refresh_legion_buttons()


func _on_active_legion_changed(slot: int) -> void:
	_refresh_legion_buttons()
	if slot > 0:
		legion_status_label.text = "军团 %d 已激活 · 右键移动/攻击" % slot


func _on_legion_creation_failed(reason: StringName) -> void:
	legion_status_label.text = (
		"请先框选怪物单位"
		if reason == &"no_monsters_selected"
		else "无法创建军团"
	)


func _refresh_legion_buttons() -> void:
	var buttons := _get_legion_buttons()
	for index in buttons.size():
		var slot := index + 1
		var count := 0
		if monster_legion_manager != null:
			count = monster_legion_manager.get_legion_units(slot).size()
		buttons[index].text = "L%d · %d" % [slot, count]
		buttons[index].disabled = count == 0
		buttons[index].button_pressed = (
			monster_legion_manager != null
			and monster_legion_manager.get_active_slot() == slot
		)


func _get_legion_buttons() -> Array[Button]:
	return [
		%LegionOneButton,
		%LegionTwoButton,
		%LegionThreeButton,
		%LegionFourButton,
	]


func _bind_monster_ai_controller() -> void:
	monster_ai_controller = get_tree().get_first_node_in_group(
		&"monster_ai_controller"
	) as MonsterAIController
	if monster_ai_controller == null:
		monster_ai_button.disabled = true
		monster_ai_status_label.text = "怪物 AI 不可用"
		return
	monster_ai_controller.ai_enabled_changed.connect(_on_monster_ai_enabled_changed)
	monster_ai_controller.defense_analysis_updated.connect(
		_on_monster_ai_analysis_updated
	)
	monster_ai_controller.attack_wave_launched.connect(
		_on_monster_ai_wave_launched
	)
	_on_monster_ai_enabled_changed(monster_ai_controller.is_ai_enabled())


func _on_monster_ai_button_pressed() -> void:
	if monster_ai_controller != null:
		monster_ai_controller.set_ai_enabled(
			not monster_ai_controller.is_ai_enabled()
		)


func _on_monster_ai_enabled_changed(is_enabled: bool) -> void:
	monster_ai_button.text = "怪物 AI：%s" % (
		"开启" if is_enabled else "已暂停"
	)
	monster_ai_status_label.text = (
		"AI 正在扫描四个防御方向"
		if is_enabled
		else "AI 已暂停，可手动控制"
	)


func _on_monster_ai_analysis_updated(scores: Dictionary) -> void:
	if monster_ai_controller == null or not monster_ai_controller.is_ai_enabled():
		return
	var weakest_direction := MonsterAIController.AttackDirection.NORTH
	var weakest_score := INF
	for direction in MonsterAIController.AttackDirection.values():
		var score := float(scores.get(direction, 0.0))
		if score < weakest_score:
			weakest_direction = direction
			weakest_score = score
	monster_ai_status_label.text = "薄弱方向：%s · 防御 %.1f" % [
		monster_ai_controller.get_direction_name(weakest_direction),
		weakest_score,
	]


func _on_monster_ai_wave_launched(
	direction: MonsterAIController.AttackDirection,
	units: Array[Node2D],
	_target: Node2D
) -> void:
	monster_ai_status_label.text = "怪物潮 ×%d 正从%s进攻" % [
		units.size(), monster_ai_controller.get_direction_name(direction)
	]


func _bind_human_ai_controller() -> void:
	human_ai_controller = get_tree().get_first_node_in_group(
		&"human_ai_controller"
	) as HumanAIController
	if human_ai_controller == null:
		human_ai_button.disabled = true
		human_ai_button.text = "人类 AI：不可用"
		return
	human_ai_controller.ai_enabled_changed.connect(_on_human_ai_enabled_changed)
	human_ai_controller.ai_tower_built.connect(_on_human_ai_tower_built)
	human_ai_controller.ai_squad_recruited.connect(_on_human_ai_squad_recruited)
	human_ai_controller.defense_response_ordered.connect(
		_on_human_ai_defense_response
	)
	human_ai_controller.expedition_dispatched.connect(
		_on_human_ai_expedition_dispatched
	)
	_on_human_ai_enabled_changed(human_ai_controller.is_ai_enabled())


func _on_human_ai_button_pressed() -> void:
	if human_ai_controller != null:
		human_ai_controller.set_ai_enabled(
			not human_ai_controller.is_ai_enabled()
		)


func _on_human_ai_enabled_changed(is_enabled: bool) -> void:
	human_ai_button.text = "人类 AI：%s" % (
		"开启" if is_enabled else "已暂停"
	)
	if not is_enabled:
		economy_status_label.text = "人类 AI 已暂停，可手动控制"


func _on_human_ai_tower_built(
	_tower: Node2D,
	direction: HumanAIController.DefenseDirection,
	_catalog_index: int
) -> void:
	economy_status_label.text = "人类 AI 已增援%s" % (
		human_ai_controller.get_direction_name(direction)
	)


func _on_human_ai_squad_recruited(
	_squad: Node2D, catalog_index: int
) -> void:
	economy_status_label.text = "人类 AI 已招募第 %d 类士兵" % (
		catalog_index + 1
	)


func _on_human_ai_defense_response(
	direction: HumanAIController.DefenseDirection,
	units: Array[Node2D],
	_target: Node2D
) -> void:
	economy_status_label.text = "人类 AI 派出 ×%d 应对%s威胁" % [
		units.size(), human_ai_controller.get_direction_name(direction)
	]


func _on_human_ai_expedition_dispatched(
	direction: HumanAIController.DefenseDirection,
	units: Array[Node2D],
	target: Node2D,
	_destination: Vector2
) -> void:
	economy_status_label.text = (
		"人类 AI 正以 ×%d 攻击可见巢穴" % units.size()
		if target != null
		else "人类 AI 派出 ×%d 侦察%s" % [
			units.size(), human_ai_controller.get_direction_name(direction)
		]
	)


func _bind_human_economy() -> void:
	human_economy = get_tree().get_first_node_in_group(&"human_economy")
	if human_economy == null:
		gold_label.text = "金币：--"
		economy_status_label.text = "人类经济系统不可用"
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
		dark_energy_label.text = "暗能量：--"
		dark_energy_rate_label.text = "怪物经济系统不可用"
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
	dark_energy_label.text = "暗能量：%d" % current_energy
	_refresh_monster_production_buttons()


func _on_monster_income_rate_changed(
	active_nests: int, energy_per_interval: int
) -> void:
	var interval := float(monster_economy.get("income_interval"))
	dark_energy_rate_label.text = "每 %.1f 秒 +%d · %d 个巢穴" % [
		interval, energy_per_interval, active_nests
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
	selected_nest_label.text = "巢穴 · %s" % _localize_nest_name(nest.name)
	monster_production_status_label.text = "选择要生产的怪物"
	_refresh_monster_production_buttons()


func _on_monster_nest_selection_cleared() -> void:
	monster_production_panel.visible = false


func _on_monster_produced(
	_monster: Node2D,
	_nest: Node2D,
	data: MonsterProductionData,
	cost: int
) -> void:
	monster_production_status_label.text = "已生产%s · 消耗 %d 暗能量" % [
		data.display_name, cost
	]
	_refresh_monster_production_buttons()


func _on_monster_production_failed(reason: StringName) -> void:
	match reason:
		&"not_enough_dark_energy":
			monster_production_status_label.text = "暗能量不足"
		&"no_safe_spawn_position":
			monster_production_status_label.text = "巢穴出口被阻挡"
		&"no_nest_selected":
			monster_production_status_label.text = "请选择一个有效巢穴"
		_:
			monster_production_status_label.text = "无法生产怪物"


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
		button.text = "%s\n%d 暗能量" % [
			data.display_name, effective_cost
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
		economy_status_label.text = "建造管理器不可用"
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
	gold_label.text = "金币：%d" % current_gold
	match reason:
		&"passive_income":
			economy_status_label.text = "被动收入 +%d" % change
		&"monster_kill":
			economy_status_label.text = "击杀怪物奖励 +%d" % change
		&"t09_test_spend":
			economy_status_label.text = "测试支出 %d" % change
		&"tower_construction":
			economy_status_label.text = "建造防御塔 %d" % change
		&"tower_upgrade":
			economy_status_label.text = "升级防御塔 %d" % change
		&"squad_recruitment":
			economy_status_label.text = "招募士兵 %d" % change
		&"starting_gold":
			economy_status_label.text = "经济系统就绪"


func _on_spend_rejected(cost: int, current_gold: int) -> void:
	economy_status_label.text = "需要 %d 金币（当前 %d）" % [cost, current_gold]


func _on_build_mode_changed(active: bool) -> void:
	build_tower_button.text = (
		"放置中 — 右键取消"
		if active
		else "建造测试塔 — 50"
	)
	if not active:
		economy_status_label.text = "已退出建造模式"


func _on_preview_validity_changed(is_valid: bool) -> void:
	economy_status_label.text = (
		"绿色：左键确认建造"
		if is_valid
		else "红色：此处不能建造"
	)


func _on_building_placed(_building: Node2D, cost: int) -> void:
	economy_status_label.text = "防御塔建造完成，消耗 %d 金币" % cost


func _on_placement_failed(reason: StringName) -> void:
	match reason:
		&"not_enough_gold":
			economy_status_label.text = "金币不足，无法建造"
		&"invalid_position":
			economy_status_label.text = "红色位置不能建造"
		_:
			economy_status_label.text = "无法进入建造模式"


func _on_tower_selection_changed(tower: Node2D) -> void:
	if tower == null:
		selected_tower_label.text = "请选择防御塔"
		upgrade_tower_button.text = "升级"
		upgrade_tower_button.disabled = true
		return
	var data = tower.call("get_tower_data")
	selected_tower_label.text = str(data.get("display_name"))
	if tower.call("is_upgraded"):
		upgrade_tower_button.text = "等级 2 — 已满级"
		upgrade_tower_button.disabled = true
	else:
		upgrade_tower_button.text = "升级 — %d 金币" % int(
			tower.call("get_upgrade_cost")
		)
		upgrade_tower_button.disabled = false


func _on_tower_upgraded(tower: Node2D, cost: int) -> void:
	_on_tower_selection_changed(tower)
	economy_status_label.text = "防御塔升级完成，消耗 %d 金币" % cost


func _on_tower_upgrade_failed(reason: StringName) -> void:
	match reason:
		&"not_enough_gold":
			economy_status_label.text = "金币不足，无法升级"
		&"already_upgraded":
			economy_status_label.text = "防御塔已经达到等级 2"
		_:
			economy_status_label.text = "请先选择一座已建造的防御塔"


func _on_squad_recruited(
	_squad: Node2D, data: HumanSquadData, cost: int
) -> void:
	economy_status_label.text = "已招募%s，消耗 %d 金币" % [
		data.display_name, cost
	]


func _on_recruitment_failed(reason: StringName) -> void:
	if reason == &"not_enough_gold":
		economy_status_label.text = "金币不足，无法招募士兵"
	else:
		economy_status_label.text = "无法招募士兵"


func _localize_nest_name(value: StringName) -> String:
	var suffix := str(value).trim_prefix("MonsterNest_")
	var names := {
		"NorthWest": "西北",
		"NorthEast": "东北",
		"EastNorth": "东北侧",
		"EastSouth": "东南侧",
		"SouthEast": "东南",
		"SouthWest": "西南",
		"WestSouth": "西南侧",
		"WestNorth": "西北侧",
	}
	return str(names.get(suffix, suffix))


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
