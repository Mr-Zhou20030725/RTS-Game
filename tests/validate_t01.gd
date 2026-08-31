extends SceneTree

const MAIN_SCENE := "res://scenes/main/main.tscn"
const GAME_MANAGER_SCRIPT := preload("res://scripts/core/game_manager.gd")


func _init() -> void:
	if not root.has_node("GameManager"):
		var game_manager := GAME_MANAGER_SCRIPT.new()
		game_manager.name = "GameManager"
		root.add_child(game_manager)
	_run_validation()


func _run_validation() -> void:
	if change_scene_to_file(MAIN_SCENE) != OK:
		_fail("Main scene could not be loaded.")
		return

	await process_frame
	await process_frame
	if current_scene == null or current_scene.name != "Main":
		_fail("Project did not start in Main.")
		return

	var start_button := current_scene.find_child("StartButton", true, false) as Button
	if start_button == null:
		_fail("Main start button was not found.")
		return

	start_button.pressed.emit()
	await process_frame
	await process_frame
	if current_scene == null or current_scene.name != "Battle":
		_fail("Main did not transition to Battle.")
		return

	var battle_manager := current_scene as Node2D
	if not battle_manager.get("is_initialized"):
		_fail("BattleManager did not initialize the battle scene.")
		return

	var return_button := current_scene.find_child("ReturnButton", true, false) as Button
	if return_button == null:
		_fail("Battle return button was not found.")
		return

	return_button.pressed.emit()
	await process_frame
	await process_frame
	if current_scene == null or current_scene.name != "Main":
		_fail("Battle did not return to Main.")
		return

	print("T01 validation passed: Main -> Battle -> Main.")
	quit()


func _fail(message: String) -> void:
	push_error("T01 validation failed: %s" % message)
	quit(1)
