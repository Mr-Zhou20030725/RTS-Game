extends Node2D

## Coordinates the active battle scene. Combat systems will be added by later tasks.

signal battle_initialized

@onready var battle_hud: Control = $HUDLayer/BattleHUD

var is_initialized := false
var player_faction := GameManager.PlayerFaction.NONE


func _ready() -> void:
	_enforce_render_layers()
	battle_hud.return_to_main_requested.connect(_on_return_to_main_requested)
	_initialize_battle()


func _enforce_render_layers() -> void:
	$Background.z_index = RenderLayers.BACKGROUND
	$BuildingPlacementManager.z_index = RenderLayers.BUILDINGS
	$HumanSquadManager.z_index = RenderLayers.UNITS
	$MonsterProductionManager.z_index = RenderLayers.UNITS
	$SelectionManager.z_index = RenderLayers.WORLD_OVERLAY
	$T04TestSquad.z_index = RenderLayers.UNITS
	$HUDLayer.layer = RenderLayers.HUD_CANVAS
	var map := $MVPMap
	for terrain_name in [
		"Ground", "NorthRegion", "SouthRegion", "CenterZone"
	]:
		map.get_node(terrain_name).z_index = RenderLayers.TERRAIN
	map.get_node("HorizontalRoute").z_index = RenderLayers.TERRAIN + 1
	map.get_node("VerticalRoute").z_index = RenderLayers.TERRAIN + 1
	map.get_node("RegionLabels").z_index = RenderLayers.TERRAIN + 2
	map.get_node("SpawnedBuildings").z_index = RenderLayers.BUILDINGS


func _initialize_battle() -> void:
	_configure_faction_session()
	is_initialized = true
	battle_initialized.emit()


func _configure_faction_session() -> void:
	var game_manager := get_node_or_null("/root/GameManager")
	if game_manager == null:
		return
	player_faction = int(game_manager.call("get_selected_player_faction"))
	if player_faction == GameManager.PlayerFaction.NONE:
		return
	var human_selected := player_faction == GameManager.PlayerFaction.HUMAN
	var controlled_faction := (
		FactionComponent.Faction.HUMAN
		if human_selected
		else FactionComponent.Faction.MONSTER
	)
	var viewer_faction := (
		FogOfWarManager.ViewerFaction.HUMAN
		if human_selected
		else FogOfWarManager.ViewerFaction.MONSTER
	)
	$FogOfWarManager.set_viewer_faction(viewer_faction)
	$SelectionManager.set_controlled_faction(controlled_faction)
	$SelectionManager.set_player_input_enabled(true)
	$BuildingPlacementManager.set_player_input_enabled(human_selected)
	$MonsterProductionManager.set_player_input_enabled(not human_selected)
	$MonsterLegionManager.set_player_input_enabled(not human_selected)
	$HumanAIController.set_ai_enabled(not human_selected)
	$MonsterAIController.set_ai_enabled(human_selected)
	if not human_selected:
		$HumanAIController.adopt_available_human_units()
	battle_hud.call("configure_player_faction", player_faction)


func get_player_faction() -> int:
	return player_faction


func _on_return_to_main_requested() -> void:
	var game_manager := get_node_or_null("/root/GameManager")
	if game_manager == null:
		push_error("GameManager autoload is unavailable.")
		return
	game_manager.call("return_to_main")
