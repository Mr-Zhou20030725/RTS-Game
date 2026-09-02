class_name HealthComponent
extends Node2D

## Reusable health state for units and buildings.

signal health_changed(current_health: float, max_health: float)
signal damaged(amount: float, source: Node)
signal healed(amount: float)
signal died(source: Node)

@export_range(1.0, 1000000.0, 1.0) var max_health := 100.0
@export var start_at_full_health := true
@export_range(0.0, 1000000.0, 1.0) var initial_health := 100.0
@export var show_debug_health_bar := true

@onready var debug_health_bar: ProgressBar = %DebugHealthBar

var current_health := 0.0
var is_dead := false


func _ready() -> void:
	max_health = maxf(max_health, 1.0)
	current_health = (
		max_health
		if start_at_full_health
		else clampf(initial_health, 0.0, max_health)
	)
	is_dead = is_zero_approx(current_health)
	_sync_debug_health_bar()
	health_changed.emit(current_health, max_health)


func take_damage(amount: float, source: Node = null) -> float:
	if amount <= 0.0 or is_dead:
		return 0.0

	var applied_damage := minf(amount, current_health)
	current_health -= applied_damage
	damaged.emit(applied_damage, source)
	health_changed.emit(current_health, max_health)
	_sync_debug_health_bar()

	if is_zero_approx(current_health):
		current_health = 0.0
		is_dead = true
		died.emit(source)

	return applied_damage


func heal(amount: float) -> float:
	if amount <= 0.0 or is_dead or is_equal_approx(current_health, max_health):
		return 0.0

	var applied_healing := minf(amount, max_health - current_health)
	current_health += applied_healing
	healed.emit(applied_healing)
	health_changed.emit(current_health, max_health)
	_sync_debug_health_bar()
	return applied_healing


func get_health_ratio() -> float:
	return current_health / max_health


func set_max_health(value: float, preserve_ratio := true) -> void:
	var next_max_health := maxf(value, 1.0)
	if is_equal_approx(next_max_health, max_health):
		return
	var previous_ratio := get_health_ratio()
	max_health = next_max_health
	if not is_dead:
		current_health = (
			max_health * previous_ratio
			if preserve_ratio
			else minf(current_health, max_health)
		)
	health_changed.emit(current_health, max_health)
	_sync_debug_health_bar()


func _sync_debug_health_bar() -> void:
	if debug_health_bar == null:
		return
	debug_health_bar.visible = show_debug_health_bar
	debug_health_bar.max_value = max_health
	debug_health_bar.value = current_health
