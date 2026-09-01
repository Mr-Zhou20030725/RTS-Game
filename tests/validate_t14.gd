extends SceneTree

const MAP_SCENE := preload("res://scenes/map/mvp_map.tscn")
const FOG_SCENE := preload("res://scenes/visibility/fog_of_war_manager.tscn")
const ECONOMY_SCENE := preload("res://scenes/economy/human_economy.tscn")
const PLACEMENT_SCENE := preload(
	"res://scenes/building/building_placement_manager.tscn"
)
const HUMAN_SCENE := preload("res://units/placeholders/test_unit.tscn")
const PROJECTILE_SCENE := preload(
	"res://scenes/combat/combat_projectile.tscn"
)
const BATTLE_SCENE := preload("res://scenes/battle/battle.tscn")


func _init() -> void:
	_run_validation()


func _run_validation() -> void:
	if not await _validate_realtime_human_fog():
		return
	if not await _validate_battle_integration():
		return
	print(
		"T14 validation passed: Human vision starts local, moving units reveal "
		+ "terrain and nests, fog returns after departure, hidden targets/effects "
		+ "cannot leak through combat or building UI, and full vision is available."
	)
	quit()


func _validate_realtime_human_fog() -> bool:
	var map := MAP_SCENE.instantiate()
	map.generation_seed = 3
	var fog := FOG_SCENE.instantiate()
	var economy = ECONOMY_SCENE.instantiate()
	economy.starting_gold = 1000
	economy.passive_income_amount = 0
	var placement = PLACEMENT_SCENE.instantiate()
	var human := HUMAN_SCENE.instantiate()
	_disable_combat(human)
	root.add_child(map)
	root.add_child(fog)
	root.add_child(economy)
	root.add_child(placement)
	root.add_child(human)
	await process_frame
	await physics_frame
	await physics_frame
	fog.refresh_visibility()

	var base := map.human_base as Node2D
	human.global_position = base.global_position + Vector2(-120, 0)
	if not fog.canvas_modulate.visible or fog.canvas_modulate.color == Color.WHITE:
		_fail("Fog CanvasModulate is not darkening the Human world canvas.")
		return false
	if fog.get_active_vision_source_count() < 2:
		_fail("Human base and unit were not registered as active vision sources.")
		return false
	var human_vision := human.get_node(
		"VisionSourceComponent"
	) as VisionSourceComponent
	if human_vision.texture == null or human_vision.get_vision_radius() <= 0.0:
		_fail("Vision source has no radial light texture or configured radius.")
		return false
	if human_vision.blend_mode != Light2D.BLEND_MODE_MIX:
		_fail("Vision sources must use mix blending so overlapping vision does not overbrighten the world.")
		return false

	var nests: Array = map.get_active_nests()
	if nests.size() != 4:
		_fail("Fog test map did not generate four nests.")
		return false
	for nest in nests:
		if fog.is_node_visible_to_human(nest) or nest.visible:
			_fail("A distant nest was visible at Human match start.")
			return false
	var target_nest := nests[0] as Node2D
	if CombatRules.can_damage(human, target_nest):
		_fail("Human combat could lock a nest hidden in fog.")
		return false

	var hidden_build_position := Vector2(1040, 520)
	if not placement.begin_tower_placement(0, hidden_build_position):
		_fail("Could not create a tower preview for the fog legality test.")
		return false
	if placement.is_preview_position_valid():
		_fail("Building preview accepted terrain hidden by fog.")
		return false
	placement.cancel_placement()

	var visible_build_position := base.global_position + Vector2(0, 200)
	if not placement.begin_tower_placement(0, visible_build_position):
		_fail("Could not create a tower preview inside Human vision.")
		return false
	if not placement.is_preview_position_valid() or not placement.confirm_placement():
		_fail("Visible open terrain rejected a legal tower placement.")
		return false
	if fog.get_active_vision_source_count() < 3:
		_fail("A placed defense tower did not add its configured vision source.")
		return false

	var projectile := PROJECTILE_SCENE.instantiate() as Node2D
	projectile.global_position = hidden_build_position
	root.add_child(projectile)
	fog.refresh_visibility()
	if projectile.visible:
		_fail("A projectile effect leaked information from inside hidden fog.")
		return false

	var reveal_destination := target_nest.global_position + (
		target_nest.global_position.direction_to(base.global_position) * 90.0
	)
	human.move_to(reveal_destination)
	var was_revealed := false
	for _frame in 360:
		await physics_frame
		fog.refresh_visibility()
		if target_nest.visible:
			was_revealed = true
			break
	if not was_revealed:
		_fail("Moving a Human unit toward darkness did not reveal the nest.")
		return false
	if not CombatRules.can_damage(human, target_nest):
		_fail("A nest inside current Human vision was not a legal target.")
		return false

	human.stop_moving()
	human.global_position = base.global_position
	for _frame in 10:
		await physics_frame
		fog.refresh_visibility()
	if target_nest.visible or fog.is_node_visible_to_human(target_nest):
		_fail("Fog did not return after the Human unit left the area.")
		return false
	if CombatRules.can_damage(human, target_nest):
		_fail("A nest became targetable again after returning to fog.")
		return false

	fog.set_human_fog_enabled(false)
	if fog.canvas_modulate.visible:
		_fail("Full-vision mode left the Human fog overlay active.")
		return false
	for nest in nests:
		if not nest.visible:
			_fail("Full-vision mode did not reveal every monster nest.")
			return false
	if not projectile.visible:
		_fail("Full-vision mode did not reveal world effects.")
		return false

	_cleanup([map, fog, economy, placement, human, projectile])
	await process_frame
	return true


func _validate_battle_integration() -> bool:
	var battle := BATTLE_SCENE.instantiate()
	root.add_child(battle)
	await process_frame
	await process_frame
	var fog := battle.get_node_or_null("FogOfWarManager") as FogOfWarManager
	var hud := battle.get_node_or_null("HUDLayer/BattleHUD") as Control
	if fog == null or not fog.is_human_fog_enabled():
		_fail("Battle scene did not load the active Human fog manager.")
		return false
	if hud == null or not hud.is_visible_in_tree():
		_fail("Screen-space HUD was hidden by the world fog canvas.")
		return false
	var map := battle.get_node("MVPMap")
	var hidden_nest_count := 0
	for nest in map.get_active_nests():
		if not nest.visible:
			hidden_nest_count += 1
	if hidden_nest_count == 0:
		_fail("Human battle start exposed the entire map and every nest.")
		return false
	_cleanup([battle])
	await process_frame
	return true


func _disable_combat(actor: Node) -> void:
	for component_name in ["MeleeAttackComponent", "RangedAttackComponent"]:
		var component := actor.get_node_or_null(component_name)
		if component != null:
			component.set("combat_enabled", false)


func _cleanup(nodes: Array) -> void:
	for node in nodes:
		if node != null and is_instance_valid(node):
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.queue_free()


func _fail(message: String) -> void:
	push_error("T14 validation failed: %s" % message)
	quit(1)
