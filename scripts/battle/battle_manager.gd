extends Node2D

## Coordinates the active battle scene. Combat systems will be added by later tasks.

signal battle_initialized

@onready var battle_hud: Control = $BattleHUD

var is_initialized := false


func _ready() -> void:
	battle_hud.return_to_main_requested.connect(_on_return_to_main_requested)
	_initialize_battle()


func _initialize_battle() -> void:
	is_initialized = true
	battle_initialized.emit()


func _on_return_to_main_requested() -> void:
	var game_manager := get_node_or_null("/root/GameManager")
	if game_manager == null:
		push_error("GameManager autoload is unavailable.")
		return
	game_manager.call("return_to_main")
