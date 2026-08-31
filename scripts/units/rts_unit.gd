class_name RTSUnit
extends CharacterBody2D

## Minimal movable and selectable RTS unit used by T04.

@export var move_speed := 150.0
@export var selection_radius := 24.0
@export var arrival_distance := 10.0
@export var separation_distance := 42.0
@export var separation_strength := 110.0

@onready var navigation_agent: NavigationAgent2D = %NavigationAgent2D
@onready var selection_indicator: Line2D = %SelectionIndicator

var is_selected := false
var _has_move_target := false
var _move_target := Vector2.ZERO


func _ready() -> void:
	selection_indicator.visible = is_selected


func _physics_process(_delta: float) -> void:
	if not _has_move_target:
		velocity = Vector2.ZERO
		return

	if (
		NavigationServer2D.map_get_iteration_id(
			navigation_agent.get_navigation_map()
		)
		== 0
	):
		velocity = Vector2.ZERO
		return

	if global_position.distance_to(_move_target) <= arrival_distance:
		_stop_moving()
		return

	var next_path_position := navigation_agent.get_next_path_position()
	var movement_direction := global_position.direction_to(next_path_position)
	if movement_direction.is_zero_approx():
		movement_direction = global_position.direction_to(_move_target)

	var desired_velocity := movement_direction * move_speed
	var separation_velocity := _calculate_separation_velocity()
	velocity = (desired_velocity + separation_velocity).limit_length(move_speed)
	move_and_slide()


func set_selected(value: bool) -> void:
	is_selected = value
	selection_indicator.visible = value


func move_to(world_position: Vector2) -> void:
	_move_target = world_position
	_has_move_target = true
	navigation_agent.target_position = world_position


func get_move_target() -> Vector2:
	return _move_target


func get_selection_radius() -> float:
	return selection_radius


func _stop_moving() -> void:
	_has_move_target = false
	velocity = Vector2.ZERO


func _calculate_separation_velocity() -> Vector2:
	var separation := Vector2.ZERO
	for other_node in get_tree().get_nodes_in_group("selectable_units"):
		if other_node == self or not other_node is Node2D:
			continue

		var other := other_node as Node2D
		var offset: Vector2 = global_position - other.global_position
		var distance: float = offset.length()
		if distance <= 0.001:
			var fallback_angle := float(get_instance_id() % 360)
			offset = Vector2.RIGHT.rotated(deg_to_rad(fallback_angle))
			distance = 1.0
		if distance >= separation_distance:
			continue

		var strength: float = 1.0 - (distance / separation_distance)
		separation += offset.normalized() * separation_strength * strength
	return separation
