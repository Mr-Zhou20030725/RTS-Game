extends Node

## Owns application-level scene flow. Battle rules belong to BattleManager.

const MAIN_SCENE := "res://scenes/main/main.tscn"
const BATTLE_SCENE := "res://scenes/battle/battle.tscn"

enum Screen {
	MAIN,
	BATTLE,
}

enum PlayerFaction {
	NONE,
	HUMAN,
	MONSTER,
}

var current_screen: Screen = Screen.MAIN
var selected_player_faction: PlayerFaction = PlayerFaction.NONE
var _scene_change_in_progress := false


func start_battle(
	player_faction: PlayerFaction = PlayerFaction.HUMAN
) -> void:
	if player_faction not in [PlayerFaction.HUMAN, PlayerFaction.MONSTER]:
		push_error("A valid player faction is required to start battle.")
		return
	selected_player_faction = player_faction
	_change_screen(BATTLE_SCENE, Screen.BATTLE)


func return_to_main() -> void:
	_change_screen(MAIN_SCENE, Screen.MAIN)


func get_selected_player_faction() -> PlayerFaction:
	return selected_player_faction


func _change_screen(scene_path: String, next_screen: Screen) -> void:
	if _scene_change_in_progress:
		return

	_scene_change_in_progress = true
	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		push_error("Unable to change scene to %s (error %s)." % [scene_path, error])
		_scene_change_in_progress = false
		return

	current_screen = next_screen
	_scene_change_in_progress = false
