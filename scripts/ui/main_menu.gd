extends Control

signal start_battle_requested(player_faction: int)

@onready var start_button: Button = %StartButton
@onready var monster_start_button: Button = %MonsterStartButton


func _ready() -> void:
	start_button.pressed.connect(_on_start_button_pressed)
	monster_start_button.pressed.connect(_on_monster_start_button_pressed)
	start_button.grab_focus()


func _on_start_button_pressed() -> void:
	start_battle_requested.emit(GameManager.PlayerFaction.HUMAN)


func _on_monster_start_button_pressed() -> void:
	start_battle_requested.emit(GameManager.PlayerFaction.MONSTER)
