class_name BattleResultManager
extends CanvasLayer

## Resolves the two destruction-based win conditions and owns the result overlay.

signal result_declared(winner: Winner, player_won: bool)
signal restart_requested
signal return_to_main_requested

enum Winner {
	NONE,
	HUMAN,
	MONSTER,
}

var mvp_map: Node2D
var player_faction := GameManager.PlayerFaction.HUMAN
var winner := Winner.NONE
var _human_base_health: HealthComponent

@onready var overlay: Control = $Overlay
@onready var result_title: Label = %ResultTitle
@onready var winner_label: Label = %WinnerLabel
@onready var reason_label: Label = %ReasonLabel
@onready var restart_button: Button = %RestartButton
@onready var return_button: Button = %ReturnButton


func _ready() -> void:
	overlay.hide()
	restart_button.pressed.connect(_on_restart_pressed)
	return_button.pressed.connect(_on_return_pressed)
	call_deferred("_bind_battle_dependencies")


func configure_dependencies(map: Node2D, selected_player_faction: int) -> void:
	_disconnect_dependencies()
	mvp_map = map
	if selected_player_faction in [
		GameManager.PlayerFaction.HUMAN,
		GameManager.PlayerFaction.MONSTER,
	]:
		player_faction = selected_player_faction
	if mvp_map == null:
		return
	if not mvp_map.active_nest_count_changed.is_connected(
		_on_active_nest_count_changed
	):
		mvp_map.active_nest_count_changed.connect(
			_on_active_nest_count_changed
		)
	_bind_human_base()


func declare_result(next_winner: Winner) -> bool:
	if winner != Winner.NONE or next_winner == Winner.NONE:
		return false
	winner = next_winner
	var player_won := _did_player_win()
	result_title.text = "胜利" if player_won else "失败"
	if winner == Winner.HUMAN:
		winner_label.text = "人类阵营获胜"
		reason_label.text = "全部怪物巢穴已被摧毁"
	else:
		winner_label.text = "怪物阵营获胜"
		reason_label.text = "人类基地已被摧毁"
	overlay.show()
	get_tree().paused = true
	result_declared.emit(winner, player_won)
	return true


func has_result() -> bool:
	return winner != Winner.NONE


func get_winner() -> Winner:
	return winner


func is_player_victorious() -> bool:
	return has_result() and _did_player_win()


func _bind_battle_dependencies() -> void:
	var battle := get_parent()
	if battle == null:
		return
	var selected_faction := GameManager.PlayerFaction.HUMAN
	if battle.has_method("get_player_faction"):
		selected_faction = int(battle.call("get_player_faction"))
	configure_dependencies(
		battle.get_node_or_null("MVPMap") as Node2D,
		selected_faction
	)


func _bind_human_base() -> void:
	if mvp_map == null:
		return
	var human_base := mvp_map.get("human_base") as Node2D
	if human_base == null or not is_instance_valid(human_base):
		return
	_human_base_health = human_base.get_node_or_null(
		"HealthComponent"
	) as HealthComponent
	if (
		_human_base_health != null
		and not _human_base_health.died.is_connected(_on_human_base_died)
	):
		_human_base_health.died.connect(_on_human_base_died)


func _disconnect_dependencies() -> void:
	if (
		mvp_map != null
		and is_instance_valid(mvp_map)
		and mvp_map.active_nest_count_changed.is_connected(
			_on_active_nest_count_changed
		)
	):
		mvp_map.active_nest_count_changed.disconnect(
			_on_active_nest_count_changed
		)
	if (
		_human_base_health != null
		and is_instance_valid(_human_base_health)
		and _human_base_health.died.is_connected(_on_human_base_died)
	):
		_human_base_health.died.disconnect(_on_human_base_died)
	_human_base_health = null


func _on_active_nest_count_changed(current_count: int) -> void:
	if current_count <= 0:
		declare_result(Winner.HUMAN)


func _on_human_base_died(_source: Node) -> void:
	declare_result(Winner.MONSTER)


func _did_player_win() -> bool:
	return (
		(winner == Winner.HUMAN and player_faction == GameManager.PlayerFaction.HUMAN)
		or (
			winner == Winner.MONSTER
			and player_faction == GameManager.PlayerFaction.MONSTER
		)
	)


func _on_restart_pressed() -> void:
	restart_requested.emit()
	get_tree().paused = false
	var game_manager := get_node_or_null("/root/GameManager")
	if game_manager != null and game_manager.has_method("restart_battle"):
		game_manager.call("restart_battle")
		return
	get_tree().reload_current_scene()


func _on_return_pressed() -> void:
	return_to_main_requested.emit()
	get_tree().paused = false
	var game_manager := get_node_or_null("/root/GameManager")
	if game_manager == null:
		push_error("GameManager autoload is unavailable.")
		return
	game_manager.call("return_to_main")
