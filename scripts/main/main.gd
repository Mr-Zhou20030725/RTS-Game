extends Node

@onready var main_menu: Control = $MainMenu


func _ready() -> void:
	main_menu.start_battle_requested.connect(_on_start_battle_requested)


func _on_start_battle_requested(player_faction: int) -> void:
	var game_manager := get_node_or_null("/root/GameManager")
	if game_manager == null:
		push_error("GameManager autoload is unavailable.")
		return
	game_manager.call("start_battle", player_faction)
