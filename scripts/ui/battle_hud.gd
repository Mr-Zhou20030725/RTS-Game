extends Control

signal return_to_main_requested

@onready var return_button: Button = %ReturnButton
@onready var gold_label: Label = %GoldLabel
@onready var economy_status_label: Label = %EconomyStatusLabel
@onready var spend_test_button: Button = %SpendTestButton

var human_economy: Node


func _ready() -> void:
	return_button.pressed.connect(_on_return_button_pressed)
	spend_test_button.pressed.connect(_on_spend_test_button_pressed)
	call_deferred("_bind_human_economy")


func _on_return_button_pressed() -> void:
	return_to_main_requested.emit()


func _bind_human_economy() -> void:
	human_economy = get_tree().get_first_node_in_group(&"human_economy")
	if human_economy == null:
		gold_label.text = "GOLD: --"
		economy_status_label.text = "HumanEconomy unavailable"
		spend_test_button.disabled = true
		return

	human_economy.gold_changed.connect(_on_gold_changed)
	human_economy.spend_rejected.connect(_on_spend_rejected)
	_on_gold_changed(human_economy.call("get_gold"), 0, &"hud_sync")


func _on_spend_test_button_pressed() -> void:
	if human_economy == null:
		return
	human_economy.call("try_spend", 50, &"t09_test_spend")


func _on_gold_changed(
	current_gold: int, change: int, reason: StringName
) -> void:
	gold_label.text = "GOLD: %d" % current_gold
	match reason:
		&"passive_income":
			economy_status_label.text = "+%d passive income" % change
		&"monster_kill":
			economy_status_label.text = "+%d monster reward" % change
		&"t09_test_spend":
			economy_status_label.text = "%d test spend" % change
		&"starting_gold":
			economy_status_label.text = "Economy ready"


func _on_spend_rejected(cost: int, current_gold: int) -> void:
	economy_status_label.text = "Need %d gold (have %d)" % [cost, current_gold]
