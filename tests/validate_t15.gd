extends SceneTree

const MAP_SCENE := preload("res://scenes/map/mvp_map.tscn")
const FOG_SCENE := preload("res://scenes/visibility/fog_of_war_manager.tscn")
const ECONOMY_SCENE := preload("res://scenes/economy/human_economy.tscn")
const PLACEMENT_SCENE := preload(
	"res://scenes/building/building_placement_manager.tscn"
)
const BATTLE_SCENE := preload("res://scenes/battle/battle.tscn")
const SCOUT_DATA := preload("res://resources/towers/scout_tower.tres")
const CORE_TOWER_DATA := [
	preload("res://resources/towers/arrow_tower.tres"),
	preload("res://resources/towers/flame_tower.tres"),
	preload("res://resources/towers/frost_tower.tres"),
	preload("res://resources/towers/arcane_tower.tres"),
]


func _init() -> void:
	_run_validation()


func _run_validation() -> void:
	if not _validate_scout_identity():
		return
	if not await _validate_build_entry():
		return
	if not await _validate_exploration_value():
		return
	print(
		"T15 validation passed: the fifth data-driven Scout Tower is buildable, "
		+ "has much weaker combat output than every core tower, and reveals a "
		+ "large hidden area without leaking vision from its build preview."
	)
	quit()


func _validate_scout_identity() -> bool:
	if SCOUT_DATA.tower_id != &"scout":
		_fail("Scout Tower Resource has the wrong identity.")
		return false
	var scout_dps: float = SCOUT_DATA.damage / SCOUT_DATA.attack_interval
	for core_data in CORE_TOWER_DATA:
		if SCOUT_DATA.vision_radius <= core_data.vision_radius:
			_fail("Scout Tower vision is not larger than every output tower.")
			return false
		var core_dps: float = core_data.damage / core_data.attack_interval
		if scout_dps >= core_dps * 0.25:
			_fail("Scout Tower combat output is not meaningfully weaker.")
			return false
	if SCOUT_DATA.attack_range >= SCOUT_DATA.vision_radius:
		_fail("Scout Tower combat range is not distinct from its vision role.")
		return false
	return true


func _validate_build_entry() -> bool:
	var battle := BATTLE_SCENE.instantiate()
	root.add_child(battle)
	await process_frame
	await process_frame
	var hud := battle.get_node("HUDLayer/BattleHUD") as Control
	var button := hud.get_node(
		"TowerBuildBar/ScoutTowerButton"
	) as Button
	if button == null or not button.is_visible_in_tree():
		_fail("Scout Tower build button is missing or hidden.")
		return false
	if not Rect2(Vector2.ZERO, hud.get_viewport_rect().size).intersects(
		button.get_global_rect()
	):
		_fail("Scout Tower build button is outside the visible viewport.")
		return false
	var placement := battle.get_node("BuildingPlacementManager")
	var catalog: Array[Resource] = placement.get_tower_data_catalog()
	if catalog.size() != 5 or catalog[4].get("tower_id") != &"scout":
		_fail("Scout Tower is not the fifth independent catalog entry.")
		return false
	button.pressed.emit()
	await process_frame
	var preview := placement.get_preview() as Node2D
	if (
		preview == null
		or preview.call("get_tower_data").get("tower_id") != &"scout"
	):
		_fail("Scout Tower HUD button did not open its configured preview.")
		return false
	placement.cancel_placement()
	_cleanup([battle])
	await process_frame
	return true


func _validate_exploration_value() -> bool:
	var map := MAP_SCENE.instantiate()
	map.generation_seed = 3
	var fog := FOG_SCENE.instantiate()
	var economy = ECONOMY_SCENE.instantiate()
	economy.starting_gold = 500
	economy.passive_income_amount = 0
	var placement = PLACEMENT_SCENE.instantiate()
	root.add_child(map)
	root.add_child(fog)
	root.add_child(economy)
	root.add_child(placement)
	await process_frame
	await physics_frame
	fog.refresh_visibility()

	var base := map.human_base as Node2D
	var target_nest := map.get_active_nests()[0] as Node2D
	var direction := base.global_position.direction_to(target_nest.global_position)
	target_nest.global_position = base.global_position + direction * 500.0
	fog.refresh_visibility()
	if target_nest.visible or fog.is_node_visible_to_human(target_nest):
		_fail("Scout exploration target was already visible before construction.")
		return false
	var build_position := base.global_position + direction * 180.0
	if not placement.begin_tower_placement(4, build_position):
		_fail("Could not begin Scout Tower placement inside existing vision.")
		return false
	if not placement.is_preview_position_valid():
		_fail("Scout Tower preview rejected a legal visible position.")
		return false
	fog.refresh_visibility()
	if target_nest.visible:
		_fail("Scout Tower build preview leaked vision before construction.")
		return false
	if not placement.confirm_placement():
		_fail("Could not construct the Scout Tower.")
		return false
	fog.refresh_visibility()
	var tower: Node2D = placement.get_placed_buildings()[0]
	var source := tower.get_node("VisionSourceComponent") as VisionSourceComponent
	if not is_equal_approx(source.get_vision_radius(), SCOUT_DATA.vision_radius):
		_fail("Placed Scout Tower did not apply its configured vision radius.")
		return false
	if not target_nest.visible or not fog.is_node_visible_to_human(target_nest):
		_fail("Constructed Scout Tower did not reveal the hidden nest area.")
		return false
	if economy.get_gold() != 500 - SCOUT_DATA.cost:
		_fail("Scout Tower construction did not deduct its exact cost.")
		return false

	_cleanup([map, fog, economy, placement])
	await process_frame
	return true


func _cleanup(nodes: Array) -> void:
	for node in nodes:
		if node != null and is_instance_valid(node):
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.queue_free()


func _fail(message: String) -> void:
	push_error("T15 validation failed: %s" % message)
	quit(1)
