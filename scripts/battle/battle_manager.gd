extends Node2D

## Coordinates the active battle scene. Combat systems will be added by later tasks.

signal battle_initialized

@onready var battle_hud: Control = $HUDLayer/BattleHUD

var is_initialized := false


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
	$T06MonsterDemo.z_index = RenderLayers.UNITS
	$T07ArcherDemo.z_index = RenderLayers.UNITS
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
	is_initialized = true
	battle_initialized.emit()


func _on_return_to_main_requested() -> void:
	var game_manager := get_node_or_null("/root/GameManager")
	if game_manager == null:
		push_error("GameManager autoload is unavailable.")
		return
	game_manager.call("return_to_main")
