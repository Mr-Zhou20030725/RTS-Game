extends Control

signal return_to_main_requested

@onready var return_button: Button = %ReturnButton


func _ready() -> void:
	return_button.pressed.connect(_on_return_button_pressed)


func _on_return_button_pressed() -> void:
	return_to_main_requested.emit()
